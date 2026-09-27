# 訂單生命週期 as-is Quint 模型（`specs/order-lifecycle`）

> 依據：ADR-018（一張 Issue、兩個 run）。不變量階段已於 PR #53 合併；`invariants.qnt` 與
> `source.md` 已凍結，本檔為模型階段的交接紀錄。
>
> **2026-09-27 重跑（修復後複驗）**：`OrderService` 已依 #57 加上狀態轉移檢查與初始狀態限制、
> `OrderEntity` 已依 #58 加上 `@Version` 樂觀鎖欄位。本檔描述的是**修復後**的模型，
> 取代 PR #55 的修復前版本。

## 涵蓋範圍

- `specs/order-lifecycle/model.qnt`：依 `OrderService` **現況**建模 `createOrder`、
  `updateOrderStatus`、`cancelOrder`，含多交易的讀取／提交交錯與 JPA 樂觀鎖。
- `specs/order-lifecycle/instances.qnt`：`oneOrder`（1）、`twoOrders`（2）、`threeOrders`（3）。
- `specs/order-lifecycle/verify.yml`：21 項 `quint run` 檢查（6 條 `INV_*` × 3 實例，
  再加 3 項 `max_steps: 30` 的深度檢查），逾時總和 1620 秒。

## 系統模型假設（對應程式）

| 模型元素 | 程式依據 |
|---|---|
| 交易分成 begin（讀取）與 commit（寫入）兩段，`pending` 為已讀未提交的交易 | `updateOrderStatus` / `cancelOrder` 都是同一交易內的 read-modify-write（`OrderService.java:101-111`、`:124-134`） |
| 同一訂單可同時有多個未提交交易 | `OrderRepository` 沒有 `@Lock`、沒有悲觀鎖查詢，讀取不互斥 |
| `createOrder` 已提交的建立寫入必為 `NEW` | `status == null → NEW`（`:40-41`）；`status != null && != NEW → InvalidOrderException`（`:42-44`），交易不提交 |
| `beginUpdate` 以「讀到的 oldStatus」檢查轉移 | `isPermittedTransition(oldStatus, newStatus)`（`:105-109`、`:148-166`）；不通過則拋 `IllegalStateException`、不提交 |
| `beginCancel` 以「讀到的狀態」檢查可取消 | `canBeCancelled`（`:128-131`、`:138-140`） |
| `currentVersion(k) == 已提交筆數 - 1` | `@Version`（`OrderEntity.java:85-87`）：INSERT 初始化為 0，之後每次成功 UPDATE 遞增 1 |
| `commit` 需 `readVersion == currentVersion` | Hibernate 的 `UPDATE ... SET version = version + 1 WHERE id = ? AND version = ?` 命中 1 列 |
| `abortOnStaleVersion` 回滾且不寫入 | 命中 0 列 → `ObjectOptimisticLockingFailureException`（`docs/orders-optimistic-locking.md`） |

`model.qnt` 的 `codePermitsTransition` / `codeCanBeCancelled` 目前直接沿用 `invariants.qnt` 的
`isAllowedTransition` / `canCancelFrom`，因為 #57 的實作與規格 R2–R5 **逐分支一致**
（見 `model.qnt` 的對照註解）。若日後程式與規格再度分歧，這兩個謂詞必須改寫成獨立的
as-is 版本，否則模型會把實作缺陷當成正確。

## 明確不涵蓋

- 快取層（`@Cacheable`／`@CachePut`／`@CacheEvict`、Hazelcast `OrderMapStore`）。
  轉移判斷所讀的狀態來自 `orderRepository.findByOrderNumber`，不經快取，因此快取新舊
  不影響 R1–R6；但快取回給呼叫端的視圖可能過期。
- `OrderRepository.updateTimestamps`（`@Modifying` JPQL 批次更新）：只改時間戳、不改 status，
  且不遞增 `@Version`。屬 `migration` 切片，不在本規格範圍。
- 事件發佈（`OrderCreatedEvent`）、稽核欄位、例外類型與訊息。
- 重試：呼叫端收到 `ObjectOptimisticLockingFailureException` 後如何重試不在模型內
  （重試會重新讀取，因此不會產生過期寫入）。
- JPA/Hibernate 的 flush 時序與 SQL 隔離級別細節；只保留「讀取與提交可交錯、
  提交時比對版本」這個足以檢查 R6 的性質。

## 執行結果（21 項全數實際執行，`quint run`，quint 0.32.0 rust backend）

| 不變量 | 三個實例的結果 | 單項牆鐘 |
|---|---|---|
| `INV_newOrderStartsNew`（R1） | 🟢 成立 | 2.92 / 3.82 / 4.40 s |
| `INV_normalFlowIsSingleStep`（R2，`max_steps` 16） | 🟢 成立 | 3.09 / 4.48 / 5.41 s |
| `INV_normalFlowIsSingleStep`（R2，`max_steps` 30） | 🟢 成立 | 3.22 / 4.89 / 6.95 s |
| `INV_cancelOnlyFromNewOrPending`（R3） | 🟢 成立 | 3.06 / 4.08 / 4.82 s |
| `INV_errorOnlyFromAllowed`（R4） | 🟢 成立 | 3.08 / 4.18 / 5.02 s |
| `INV_onlyPermittedTransitions`（R5） | 🟢 成立 | 3.12 / 4.25 / 5.14 s |
| `INV_committedWritesAreSequentialAndFresh`（R6） | 🟢 成立 | 3.12 / 4.32 / 5.29 s |

單項最大牆鐘 **6.95 秒**（Issue 上限 600 秒）；21 項合計 88.66 秒。沒有任何反例，
因此 `specs/order-lifecycle/traces/` 這次沒有新的 ITF（目錄內既有檔案是 PR #55 修復前的紀錄，
由 CI 管理）。

### witness 覆蓋（10000 條軌跡中命中數，oneOrder / twoOrders / threeOrders）

| witness | 情境 | 命中數 |
|---|---|---|
| `WIT_orderCreatedAsNew` | 訂單確實被建立並提交 | 10000 / 10000 / 10000 |
| `WIT_normalForwardStep` | 正常流程確實前進了一階 | 828 / 1494 / 1827 |
| `WIT_deliveredReached` | 走完整條 `NEW → … → DELIVERED` | 47 / 108 / 84 |
| `WIT_cancelCommitted` | 確實有訂單被取消並提交 | 7229 / 9079 / 9289 |
| `WIT_errorCommitted` | 確實有訂單進入 `ERROR` | 2509 / 4074 / 4835 |
| `WIT_statusTransitionCommitted` | 確實發生過狀態轉移 | 9969 / 9947 / 9929 |
| `WIT_terminalStateReached` | 確實有訂單走到終態 | 9809 / 9854 / 9841 |
| `WIT_concurrentTxnsOnSameOrder` | 同一訂單上同時有 2 個以上未提交交易 | 4167 / 6332 / 7581 |
| `WIT_staleReaderExists` | 有交易握著已被別人遞增的過期版本 | 4137 / 6128 / 6835 |
| `WIT_staleWriteRejected` | 樂觀鎖確實攔下一次過期寫入 | 4096 / 5867 / 5940 |

全部 witness 命中數 > 0，因此「全部成立」不是空真（vacuous）。

### 敏感度（mutation）檢查

「全部成立」本身不能證明模型有辨識力，因此另外以三個**暫時的**模型變異（未提交、
在工作區外執行後刪除）確認模型會抓到修復前的行為：

| 變異 | 等同於 | 結果 |
|---|---|---|
| 移除 `commit` 的 `txn.readVersion == currentVersion(...)` | #58 修復前（無 `@Version`） | 🔴 `INV_committedWritesAreSequentialAndFresh`、`INV_cancelOnlyFromNewOrPending` 違反 |
| 移除 `beginUpdate` 的 `codePermitsTransition(...)` | #57 修復前（無轉移檢查） | 🔴 `INV_onlyPermittedTransitions` 等違反 |
| `createOrder` 改寫入 `SHIPPED` | #57 修復前（不限制初始狀態） | 🔴 `INV_newOrderStartsNew` 違反 |

### `mode: verify`（Apalache 窮盡）的量測

已實測可行但未納入 `verify.yml`：`oneOrder` `max_steps 4` → 14.0 秒、`max_steps 8` → 34.0 秒
（`INV_committedWritesAreSequentialAndFresh`）。未納入的原因：

1. 需要覆寫 `HOME` 才能建立 `~/.quint/apalache-dist-0.56.1`（agent 沙箱下為 `EACCES`），
   CI 環境是否可行未經驗證；
2. 會在工作目錄產生 `_apalache-out/`，而 `.gitignore` 目前沒有收錄它
   （`.gitignore` 不在模型階段的白名單內，本次不修改）。

是否開啟列為未決事項。

## 何時更新

程式改變下列任一行為時，**先**更新模型並重跑 `verify.yml`，再改程式：

- `isPermittedTransition` / `canBeCancelled` 的分支（此時 `codePermitsTransition` 必須改成
  獨立的 as-is 謂詞，不能再沿用 `invariants.qnt`）；
- `createOrder` 對初始狀態的限制；
- `@Version` 的存在或鎖定策略（改成悲觀鎖、加 `@Lock`、或改用 `SELECT ... FOR UPDATE`）；
- 新增任何不經 `OrderService` 的 status 寫入路徑（目前只有 `OrderService`，
  已以 `grep setStatus` 確認）。
