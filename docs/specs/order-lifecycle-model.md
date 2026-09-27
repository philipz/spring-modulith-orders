# 訂單生命週期 as-is Quint 模型（`specs/order-lifecycle`）

> 依據：ADR-018（一張 Issue、兩個 run）。不變量階段已於 PR #53 合併；`invariants.qnt` 與 `source.md` 已凍結，本檔為模型階段的交接紀錄。

## 涵蓋範圍

- `specs/order-lifecycle/model.qnt`：依 `OrderService` 現況建模 `createOrder`、`updateOrderStatus`、`cancelOrder`。
- `specs/order-lifecycle/instances.qnt`：`oneOrder`（1）、`twoOrders`（2）、`threeOrders`（3）。
- `specs/order-lifecycle/verify.yml`：每條 `INV_*` 於三個實例各一項 `quint run` 檢查（共 18 項，逾時總和 1620 秒）。

## 系統模型假設

- `OrderEntity`、`BaseEntity` 無 `@Version`；`OrderRepository` 無 `@Lock` 或鎖定查詢。因此沒有樂觀／悲觀鎖，交易是 read-modify-write，可能以過期讀取覆寫已提交狀態。
- 交易以「begin（讀取）→ commit（寫入）」兩段建模；`orders` 只記錄「已提交」的寫入序列（`StatusWrite.readStatus` 為該次讀到的已提交狀態）。
- 訂單編號以符號字串表示（程式為 UUID，在此抽象）。
- `createOrder` 只在 `status == null` 時設為 `NEW`（`OrderService.java:39-41`）；非 null 的 status 原樣存下，故建立時的寫入可為任意 `OrderStatus`。
- `updateOrderStatus` 無任何轉移檢查（`OrderService.java:102-104`）。
- `cancelOrder` 讀取現況後檢查 `canBeCancelled`（`OrderService.java:121-124`），但提交時不重新檢查讀到的狀態。

## 明確不涵蓋

- 快取（`@Cacheable`／`@CachePut`／`@CacheEvict`）、事件發佈、時間戳與稽核欄位。
- JPA/Hibernate 的實際 flush 時序與 SQL 隔離細節；只保留「讀取與提交可交錯」這個足以檢查 R6 的性質。
- `findOrder`／`findOrders` 等查詢路徑。
- 例外類型與訊息（`OrderNotFoundException`、`IllegalStateException`）：模型只表示「未提交、已提交狀態不變」。

## 執行結果（`quint run`，18 項全數實際執行）

| 不變量 | 結果 | 單項牆鐘 |
|---|---|---|
| 全部 6 條 `INV_*` | 🔴 違反（候選發現，未回放） | 約 4.3–4.5 秒 |

反例 ITF 由 CI 寫入 `specs/order-lifecycle/traces/`。摘要：

- `INV_newOrderStartsNew`：`createOrder` 可寫入非 `NEW` 的狀態。正式呼叫路徑 `OrderMapper.convertToEntity` 固定傳 `NEW`（`OrderMapper.java:16-18`）；此反例來自直接呼叫 `OrderService.createOrder`，屬潛在缺陷。
- `INV_normalFlowIsSingleStep`／`INV_onlyPermittedTransitions`：`updateOrderStatus` 可任意跳階、同值寫入、或由終態回到其他狀態。
- `INV_cancelOnlyFromNewOrPending`：`updateOrderStatus(..., CANCELLED)` 繞過 `cancelOrder` 的 `canBeCancelled`；亦有「讀取時為 NEW、提交前已前進到 DELIVERED」的過期讀取取消。
- `INV_errorOnlyFromAllowed`：`updateOrderStatus(..., ERROR)` 可由 `SHIPPED` 等非允許來源進入。
- `INV_committedWritesAreSequentialAndFresh`：無鎖導致並行交易以過期讀取覆寫。代表反例：同一訂單兩個交易同讀 `NEW`，先提交 `DELIVERED`、後提交 `CANCELLED`（等同「已出貨的訂單被取消」）。

## 何時更新

當程式改變下列行為時，先更新模型並重跑 `verify.yml`：加入轉移檢查、加入 `@Version`／`@Lock`，或讓 `createOrder` 強制 `NEW`。模型是「修復前」的紀錄，不會自動跟著程式更新。
