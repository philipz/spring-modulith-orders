# Circuit Breaker as-is 模型紀錄（specs/circuit-breaker）

> ADR-018 模型階段。不變量出自 `specs/circuit-breaker/source.md`（已核准凍結）；
> 本模型依 `CacheErrorHandler` 程式現況建模，**包含缺陷**。本文件由模型階段產出，
> 供審查者理解模型範圍與反例。
>
> **2026-09-27 修復後複驗**：`CacheErrorHandler` 已依 Issue #56 修復（半開失敗重新
> 開路並重新計時、半開只放行 1 個試探請求、Closed 失敗計數依時間視窗歸零）。本文件
> 與 `model.qnt` 依**目前 trunk 的程式**重建，取代上一輪（PR #54）的模型。

## 建模對象

`src/main/java/com/sivalabs/bookstore/orders/cache/CacheErrorHandler.java`：

| 方法 | 行號 | 模型中的對應 |
| --- | --- | --- |
| `executeWithFallback` / `executeVoidOperation` | :51-91 | `beginRequest`（閘門放行）／`rejectRequest`（閘門擋下） |
| `shouldBypassOperation` | :155-171 | `gateClosedAdmits`／`gateTimerExpired`／`gateTrialAdmits`／`gateAdmits` |
| `handleCacheError` | :93-114 | `failWhileOpenPath`（`circuitOpen` 為真的分支）／`failWhileClosed` |
| `registerClosedStateFailure` | :122-131 | `failWhileClosed` 的 `windowExpired`／`failures` |
| `recordSuccess` | :200-209 | `finishSuccess` |
| `checkCacheHealth` | :173-188 | `healthCheckPass`／`healthCheckThrows` |
| `resetErrorState` | :222-231 | `resetState` |
| `openCircuit` / `closeCircuit` | :233-247 | `doOpenCircuit`／`finishSuccess` 與 `healthCheckPass` 內的關路分支 |
| `isCircuitOpen` | :133-145 | 純讀取、不改狀態，其時間判定等於 `circuitState == HalfOpen`；不另設步驟 |

（`shouldFallbackToDatabase`、`getCacheErrorStats`、各 getter 為觀測/統計，無不變量涵蓋，未建模。
`checkCacheHealth` 的 `healthCheck` 回 `false` 分支只寫 log、不改狀態，也未設步驟。）

## 檔案

| 檔案 | 內容 |
| --- | --- |
| `invariants.qnt` | 已核准的不變量與狀態詞彙（本階段不修改） |
| `model.qnt` | as-is 行為、`step`、情境 witness `WIT_*` |
| `instances.qnt` | 四組具體常數實例 |
| `verify.yml` | 實例 × 不變量 × 步數 × 逾時 × witness（不宣告預期結果） |
| `traces/` | CI 執行時寫入的反例 ITF（agent 不寫入） |

`model.qnt` 以 `import invariants.* from "./invariants"` 與 `export invariants.*` 為
`module model` 的前兩道敘述（Quint 0.32.0 要求檔案必須以 `module` 起始，故 import/export
位於模組內、而非檔案第一行）。缺 `export` 會使 `instances.qnt` 看不到 `INV_*`（`QNT404`）。

## 併發抽象

- **THREADS 個呼叫端**，各有一個 `pc`（`Idle`／`Running`），可同時有多個請求在飛行中。
- **每個 public method 的呼叫視為一個原子步驟**，唯一例外是「閘門放行 → 受保護操作
  回來」之間的窗口（`beginRequest` → `finishSuccess`／`failWhile*`）：那是真正以毫秒
  計的窗口（打到 Redis），也是實務上交錯確實會發生的地方。
- **method 內部相鄰 volatile 讀寫之間的奈秒級窗口不建模**。最值得注意的一個：
  `shouldBypassOperation` 先讀 `circuitOpenedAt`（:160）再做
  `halfOpenTrialActive.compareAndSet`（:162），兩者之間若有另一執行緒 `openCircuit()`
  （重設 `circuitOpenedAt` 與試探名額），本執行緒可能拿著過期的 `openedAt` 快照通過
  CAS，在**新的 Open 期間**被放行。本模型的原子閘門抽象看不到這個交錯——這是刻意的
  抽象選擇（以毫秒級窗口為建模邊界），列為未決事項交人類裁定。
- `admittedWhileOpen` 在**請求放行的當下**依當時狀態計數（Issue #50 指定）。上一輪在
  請求結束時才計數，把「Closed 時放行、執行期間才開路」的請求誤算成 Open 放行，
  該次違反經人工判定為模型假象。

## 輔助變數的生命週期（規格側，程式無對應欄位）

`halfOpenAdmitted`／`halfOpenSuccesses`／`halfOpenFailed`／`lastHalfOpenFailureAt`
都是「本次 Open→Half-Open 情境」範圍的計量：

| 變數 | 設定時機 | 歸零時機 |
| --- | --- | --- |
| `halfOpenAdmitted` | 放行當下狀態為 Half-Open | `openCircuit`（新情境）、關路 |
| `halfOpenSuccesses` | 試探請求成功（`th.trial`） | `openCircuit`（新情境）、`resetErrorState` |
| `halfOpenFailed` | 試探請求失敗 | 關路、**Open 期滿**（`tick` 跨過 `circuitOpenDuration`） |
| `lastHalfOpenFailureAt` | 試探請求失敗 | 關路（`circuitOpenedAt` 同時回到 -1） |

`halfOpenFailed` 在 Open 期滿時歸零，是因為該次失敗所要求的「回到 Open」已由這段
Open 期間履行完畢；若讓它跨越期滿繼續為真，時間一到狀態變成 Half-Open 就會產生
與程式缺陷無關的假違反。同理，關路時必須清掉 `lastHalfOpenFailureAt`，否則
`closeCircuit` 把 `circuitOpenedAt` 設回 -1 會讓 `INV_halfOpenFailureRestartsTimer`
出現假違反。**這是輔助變數的作用域選擇，不改動任何被建模的程式行為**；列為未決事項。

## 常數範圍（Q21）

| 常數 | 值 | 依據 |
| --- | --- | --- |
| `failureThreshold` | 1、2、3 | `CacheErrorHandler.java:35` `@Value` 注入、建構子 :38 未檢查範圍；涵蓋邊界（1）與奇偶 |
| `circuitOpenDuration` | 1、2、3 | `CacheErrorHandler.java:36` `@Value`、:39 未檢查；涵蓋邊界（1）與奇偶 |
| `failureWindow` | 2、3、4 | `CacheErrorHandler.java:37` `@Value`、:40 未檢查；涵蓋奇偶 |
| `THREADS` | `Set(1)`、`Set(1,2)`、`Set(1,2,3)` | `@Component` 單例（:14-15），程式未限制併發呼叫端；涵蓋邊界（無併發）與奇偶 |
| `successThreshold` | 1 | 程式無對應設定（`recordSuccess` :205-208 單次成功即關路）；Issue #50 採規格最小合法值 |
| `maxHalfOpenRequests` | 1 | 程式無對應設定；以 `AtomicBoolean halfOpenTrialActive`（:27、:162）結構上只放行 1 個；Issue #50 採規格最小合法值 |

未使用任何程式本身沒有的 `assume`／`assert` 來縮小範圍。

## 量測與限制

- 全部檢查採 **`mode: run`（隨機模擬）**：`mode: verify` 需要 Apalache，本環境
  `quint verify` 在 `$HOME/.quint` 解壓時 `EACCES`（實測退出碼 1、牆鐘 2.07s），
  量不到的數字不宣告。因此「成立」只代表抽樣中未見反例，**不是證明**。
- 單次檢查實測牆鐘：`holds` 類約 7.5–8.5 秒（`--max-steps=24 --max-samples=20000`）、
  違反類 < 2 秒；Issue #50 的上限是 600 秒。`verify.yml` 逾時總和 1480 秒（上限 1800）。
- 只建模單一 breaker 實例；未建模多 shard／多資源（`source.md`
  §Problems and considerations 的 Resource differentiation）與多區域。
- 未建模 Retry pattern 的組合、manual override、failed-request replay、
  `LocalDateTime.now()` 的牆鐘跳躍與時鐘漂移（模型用單一邏輯時鐘 `now`）。

## 如何重跑

```bash
QUINT=/home/runner/work/software_factory/software_factory/node_modules/.bin/quint
cd specs/circuit-breaker
$QUINT typecheck instances.qnt
$QUINT run instances.qnt --main=cb_t1_d1_w2 --invariant=INV_halfOpenFailureReopens \
  --max-steps=24 --max-samples=20000 --witnesses WIT_halfOpenTrialFailed
```

或跑 harness 的集中驗證（與 CI 同一條路徑；`--quint` 省略時預設
`node_modules/.bin/quint`，需在 harness 根目錄執行）：

```bash
cd /home/runner/work/software_factory/software_factory
node dist/cli/factory-spec-verify.js --phase model --spec-name circuit-breaker \
  --target target --summary /tmp/spec-verify.md
```

## Quint 陷阱（本輪踩到並修正）

`x' = a or b` 會被解析成 `(x' = a) or b`——賦值的優先序比 `or` 高，`or` 的右運算元
變成另一個合取項，`x` 實際上被賦成 `a`。型別檢查不會報錯，只會讓 witness 永遠不可達
（本輪 `rejectedWhileOpen` 一開始 0/20000）。**latch 形式的賦值一律加括號**：
`x' = (a or b)`。

## 結果判定

結果一律以 CI 依 `verify.yml` 重新執行為準（`traces/` 由 CI 寫入）。以下是 agent 端以
harness `factory-spec-verify`（與 CI 同一條路徑、quint 0.32.0）實測的結果：退出碼 **0**、
`ok=true`、`mismatches=[]`，全 20 項檢查總牆鐘 **136.62 秒**。

| 不變量 | 結果 | 說明 |
| --- | --- | --- |
| `INV_openRejectsOperation` | ✅ 成立（witness 可達） | `shouldBypassOperation` 在 Open 期間一律 `return true`；放行只發生在 Closed 或搶到試探名額時 |
| `INV_closedFailureCountNotExceeded` | ✅ 成立（witness 可達） | 達門檻的那次失敗在同一次 `handleCacheError` 內就 `openCircuit()` |
| `INV_openRequiresThresholdReached` | ✅ 成立（witness 可達） | 關路一定同時把 `consecutiveFailures` 歸零，不存在「開著但計數低於門檻」的狀態 |
| `INV_closedFailureCounterResetsPeriodically` | 🔴 違反（候選發現，未回放） | 見下節 |
| `INV_halfOpenBoundedRequests` | ✅ 成立（witness 可達） | `halfOpenTrialActive` 的 CAS（:162）每個 Open 期間只放行 1 個試探請求（#56） |
| `INV_halfOpenClosesAfterSuccessThreshold` | ✅ 成立（witness 可達） | `successThreshold = 1` 下語意一致（見未決事項） |
| `INV_halfOpenFailureReopens` | ✅ 成立（witness 可達） | `handleCacheError` 的 `if (circuitOpen) { openCircuit(); return; }`（:102-108，#56） |
| `INV_halfOpenFailureRestartsTimer` | ✅ 成立（witness 可達） | 同一個 `openCircuit()` 把 `circuitOpenedAt` 設為 `now`（:235） |

上一輪（PR #54）的 5 條違反，有 4 條在 #56 修復後不再重現、1 條（`INV_openRejectsOperation`）
經人工判定為模型假象且本輪已改為放行當下計數。

### 唯一的候選發現：`INV_closedFailureCounterResetsPeriodically`

`source.md` §Solution：「The failure counter for the **Closed** state is time based.
It automatically resets at periodic intervals.」

`registerClosedStateFailure`（:122-131）確實引入了時間視窗，但**重設是惰性的**：只有
「下一次失敗抵達」時才會比較 `Duration.between(windowStart, now) > failureWindow` 並把
計數重設為 1。視窗過期後若沒有新的失敗，`consecutiveFailures` 與 `firstFailureAt`
都維持舊值——`getConsecutiveFailureCount()`（:249-251，public API）讀到的是過期計數。
邊界上還有 `>` 與不變量的 `>=` 落差：`elapsed == failureWindow` 那一刻程式仍歸屬舊視窗。

最短反例（`cb_t2_d3_w4_c1`，**單一執行緒**，`failureWindow = 4`）：
`now=2` 發生一次失敗 → `consecutiveFailures=1`、`windowStartedAt=2`；接著只是時間推進到
`now=6` → `now - windowStartedAt = 4 >= 4` 而 `consecutiveFailures` 仍為 1。
三個實例（含單執行緒）都在 < 2 秒內找到反例，**與併發交錯無關**。

違反是**候選發現（未回放）**：請開 `agent-fix-bug` 工單，由 01-test 的紅燈測試回放到真實
程式確認（ADR-018 Q31）。本工作項不修改 `src/`。
