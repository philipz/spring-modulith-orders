# Circuit Breaker as-is 模型紀錄（specs/circuit-breaker）

> ADR-018 模型階段。不變量出自 `specs/circuit-breaker/source.md`（已核准凍結）；
> 本模型依 `CacheErrorHandler` 程式現況建模，**包含缺陷**。本文件由模型階段產出，
> 供審查者理解模型範圍與反例。
>
> **2026-09-27 第二次修復後複驗**：`CacheErrorHandler` 在 #56 之後又依 Issue #73 修復
> 失敗計數的時間視窗——時間來源改為可注入的 `Clock`（:23、:48-53）、視窗比較改為
> 大於或等於（`hasFailureWindowElapsed` :153-155）、**讀取計數時若視窗已過期即回傳 0**
> （`getConsecutiveFailureCount` → `expireElapsedFailureWindow`，:275-293）。本文件與
> `model.qnt` 依**目前 trunk 的程式**重建，取代上一輪（PR #71）的模型。
>
> **2026-09-27 不變量重做後複驗（本輪，PR #79 之後）**：上一輪（PR #78）唯一的候選發現
> `INV_openRequiresThresholdReached` 經**人工裁定為不變量寫法過強**——引文規定的是
> Closed → Open **轉移當下**的條件，不是整段 Open 期間的狀態條件。人類據此重跑不變量階段
> 並只改寫該條（PR #79），同時在 `invariants.qnt` 新增 `var failuresAtLastOpening`。
> **`CacheErrorHandler` 本輪沒有任何變更**（最後一次修改仍是 #73），因此本輪的模型變更
> **只有 ghost 變數的維護與 witness**，所有描述程式行為的 action 逐字沿用 PR #78。

## 建模對象

`src/main/java/com/sivalabs/bookstore/orders/cache/CacheErrorHandler.java`：

| 方法 | 行號 | 模型中的對應 |
| --- | --- | --- |
| `executeWithFallback` / `executeVoidOperation` | :63-103 | `beginRequest`（閘門放行）／`rejectRequest`（閘門擋下） |
| `shouldBypassOperation` | :180-197 | `gateClosedAdmits`／`gateTimerExpired`／`gateTrialAdmits`／`gateAdmits` |
| `handleCacheError` | :105-126 | `failWhileOpenPath`（`circuitOpen` 為真的分支）／`failWhileClosed` |
| `registerClosedStateFailure` | :137-146 | `failWhileClosed` 的 `windowExpired`／`failures` |
| `hasFailureWindowElapsed` | :153-155 | `failureWindowElapsedAt`（#73 起邊界含等於） |
| `getConsecutiveFailureCount` + `expireElapsedFailureWindow` | :275-278、:287-293 | `readFailureCount`／`observedFailureCount`（#73 新增的讀取路徑） |
| `recordSuccess` | :226-235 | `finishSuccess` |
| `checkCacheHealth` | :199-214 | `healthCheckPass`／`healthCheckThrows` |
| `resetErrorState` | :248-257 | `resetState` |
| `openCircuit` / `closeCircuit` | :259-273 | `doOpenCircuit`／`finishSuccess` 與 `healthCheckPass` 內的關路分支 |
| `isCircuitOpen` | :157-170 | 純讀取、不改狀態，其時間判定等於 `circuitState == HalfOpen`；不另設步驟 |

（`shouldFallbackToDatabase`、`getCacheErrorStats`、其餘 getter 為觀測/統計，無不變量涵蓋，
未建模。`checkCacheHealth` 的 `healthCheck` 回 `false` 分支只寫 log、不改狀態，也未設步驟。）

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

## 失敗計數的兩層表示（#73 的核心語意）

`invariants.qnt` 的 `consecutiveFailures` 要對應到程式裡的哪個值，是本輪**唯一的關鍵
建模判斷**，直接決定兩條不變量的結果。程式在 #73 之後有兩個不同的值：

| 模型變數 | 對應程式 | 語意 |
| --- | --- | --- |
| `memoFailureCount`（模型專屬） | `AtomicInteger consecutiveFailures` 這個**欄位**（:25） | 歸零是**惰性**的：只有下一次失敗抵達（:140-144）、一次讀取（:287-293）或關路／重設才 materialize |
| `consecutiveFailures`（`invariants.qnt` 的詞彙） | **任何讀取者實際拿到的值** | 視窗過期即 0 |

選擇「讀取者拿到的值」的依據：程式裡讀到這個計數的**每一條路徑**都會先套用視窗過期，
沒有例外——

- 對外只有 `getConsecutiveFailureCount()`（:275-278），它先呼叫 `expireElapsedFailureWindow()`；
  兩個讀取者 `CacheHealthIndicator.java:180`、`OrdersInfoContributor.java:34` 都走這裡。
- 對內只有 `registerClosedStateFailure`（:140），視窗已過期時不是 `+1` 而是重設為 1。

因此 `memoFailureCount` 的舊值**沒有任何觀察者、也沒有任何判斷**看得到，等價於一個
memoization 快取。兩個值都保留在模型狀態裡，反例 ITF 會同時顯示，審查者可自行比對。
Issue #50 的第二次重跑指示即為「讀取計數時若視窗已過期即回傳 0……照實建模這個語意」。
**這個對應關係列為未決事項 2 交人類裁定**：改採「欄位」對應會讓
`INV_closedFailureCounterResetsPeriodically` 重新違反（惰性歸零）、
`INV_openRequiresThresholdReached` 一樣違反（讀取後欄位歸零），即兩條都違反。

## 併發抽象

- **THREADS 個呼叫端**，各有一個 `pc`（`Idle`／`Running`），可同時有多個請求在飛行中。
- **每個 public method 的呼叫視為一個原子步驟**，唯一例外是「閘門放行 → 受保護操作
  回來」之間的窗口（`beginRequest` → `finishSuccess`／`failWhile*`）：那是真正以毫秒
  計的窗口（打到 Redis），也是實務上交錯確實會發生的地方。
- **method 內部相鄰 volatile 讀寫之間的奈秒級窗口不建模**。最值得注意的一個：
  `shouldBypassOperation` 先讀 `circuitOpenedAt`（:185）再做
  `halfOpenTrialActive.compareAndSet`（:188），兩者之間若有另一執行緒 `openCircuit()`
  （重設 `circuitOpenedAt` 與試探名額），本執行緒可能拿著過期的 `openedAt` 快照通過
  CAS，在**新的 Open 期間**被放行。本模型的原子閘門抽象看不到這個交錯——這是刻意的
  抽象選擇（以毫秒級窗口為建模邊界），列為未決事項交人類裁定。
- `admittedWhileOpen` 在**請求放行的當下**依當時狀態計數（Issue #50 指定）。

## 輔助變數的生命週期（規格側，程式無對應欄位）

`halfOpenAdmitted`／`halfOpenSuccesses`／`halfOpenFailed`／`lastHalfOpenFailureAt`
都是「本次 Open→Half-Open 情境」範圍的計量：

| 變數 | 設定時機 | 歸零時機 |
| --- | --- | --- |
| `halfOpenAdmitted` | 放行當下狀態為 Half-Open | `openCircuit`（新情境）、關路 |
| `halfOpenSuccesses` | 試探請求成功（`th.trial`） | `openCircuit`（新情境）、`resetErrorState` |
| `halfOpenFailed` | 試探請求失敗 | 關路、**Open 期滿**（`tick` 跨過 `circuitOpenDuration`） |
| `lastHalfOpenFailureAt` | 試探請求失敗 | 關路（`circuitOpenedAt` 同時回到 -1） |

`failuresAtLastOpening`（本輪由 `invariants.qnt` 新增）是另一種輔助變數——**不是情境範圍的
計量，而是轉移的歷史紀錄**：

| 變數 | 設定時機 | 歸零時機 |
| --- | --- | --- |
| `failuresAtLastOpening` | `failWhileClosed` 開路當下，寫入 `registerClosedStateFailure()` 的回傳值（:122-125） | **從不歸零**（`init` 為 0） |

三個相關的建模判斷，逐條說明：

1. **只有 Closed → Open 寫入。** `failWhileOpenPath`（:114-120 的 `if (circuitOpen)` 分支）
   是「已經開著的 breaker 重新計時」，不是 Closed → Open 轉移，故不更新——這正是
   `invariants.qnt:48-51` 對該變數的宣告，也是不變量刻意不涵蓋該路徑的原因
   （`source.md`：「enters the **Open** state immediately」）。
2. **關路不歸零。** 變數語意是「**最近一次** Closed → Open 轉移當下的失敗數」；關路
   （`closeCircuit` :267-273、`resetErrorState` :248-257）不會讓那次轉移沒發生過。
   這裡有另一種寫法（關路時歸零），兩者在本模型下對不變量結果**沒有差異**，因為模型中
   Closed → Open 的唯一入口就是 `failWhileClosed` 的 `opens` 分支（`failWhileOpenPath`
   要求 `circuitOpen` 已為真）；採「不歸零」是因為它逐字符合 `invariants.qnt` 的宣告。
   **列為未決事項 3。**
3. **程式沒有這個欄位。** 它是規格側的 ghost 變數，只被不變量讀取，不影響任何被建模的
   程式行為（不出現在任何 guard 裡）。

`halfOpenFailed` 在 Open 期滿時歸零，是因為該次失敗所要求的「回到 Open」已由這段
Open 期間履行完畢；若讓它跨越期滿繼續為真，時間一到狀態變成 Half-Open 就會產生
與程式缺陷無關的假違反。同理，關路時必須清掉 `lastHalfOpenFailureAt`，否則
`closeCircuit` 把 `circuitOpenedAt` 設回 -1 會讓 `INV_halfOpenFailureRestartsTimer`
出現假違反。**這是輔助變數的作用域選擇，不改動任何被建模的程式行為**；列為未決事項。

## 常數範圍（Q21）

| 常數 | 值 | 依據 |
| --- | --- | --- |
| `failureThreshold` | 1、2、3 | `CacheErrorHandler.java:37` `@Value` 注入、建構子 :49 未檢查範圍；涵蓋邊界（1）與奇偶 |
| `circuitOpenDuration` | 1、2、3 | `CacheErrorHandler.java:38` `@Value`、:50 未檢查；涵蓋邊界（1）與奇偶 |
| `failureWindow` | 2、3、4 | `CacheErrorHandler.java:39` `@Value`、:51 未檢查；涵蓋奇偶 |
| `THREADS` | `Set(1)`、`Set(1,2)`、`Set(1,2,3)` | `@Component` 單例（:15-16），程式未限制併發呼叫端；涵蓋邊界（無併發）與奇偶 |
| `successThreshold` | 1 | 程式無對應設定（`recordSuccess` :226-235 單次成功即關路）；Issue #50 採規格最小合法值 |
| `maxHalfOpenRequests` | 1 | 程式無對應設定；以 `AtomicBoolean halfOpenTrialActive`（:29、:188）結構上只放行 1 個；Issue #50 採規格最小合法值 |

未使用任何程式本身沒有的 `assume`／`assert` 來縮小範圍。

## 量測與限制

- 全部檢查採 **`mode: run`（隨機模擬）**：`mode: verify` 需要 Apalache，本環境
  `quint verify` 在 `$HOME/.quint` 解壓時 `EACCES`（實測退出碼 1），量不到的數字不宣告。
  因此「成立」只代表抽樣中未見反例，**不是證明**。
- 單次檢查實測牆鐘（本輪，quint 0.32.0）：
  - `--max-steps=24 --max-samples=20000` → **9.0–9.8 秒**；
  - `--max-steps=40 --max-samples=20000` → **13.6–14.8 秒**；
  - `--max-steps=40 --max-samples=100000` → **57.4–61.1 秒**（三項稀有 witness 用）。
  - `--max-steps=60 --max-samples=40000` → **41.2 秒**（單執行緒實例用）。

  Issue #50 的單次上限是 600 秒，最慢的一項是它的 **10%**。全 21 項檢查總牆鐘
  **360 秒**（放大稀有 witness 前是 184 秒）。`verify.yml` 逾時總和 **1760 秒**
  （上限 1800）；每項逾時對實測牆鐘保留 2.4× 以上的餘裕。
- **稀有 witness 的抽樣規模是量出來的，不是猜的。** 上一輪有兩項檢查的 witness 落在
  0 次、另兩項只有 1–2 次（等於換個隨機種子就可能變 0 ——「成立」會變成假綠燈）。
  本輪逐項量測後放大（三次最佳化嘗試，全部記錄於 `verify.yml` 的註解）：

  | 檢查 | 上一輪（24 步／20000） | 本輪設定 | 本輪 witness | 牆鐘 |
  | --- | --- | --- | --- | --- |
  | `cb_t3_d1_w2_c3` / `INV_halfOpenFailureReopens` | **0** | 40 步／100000 | 4 | 61.1s |
  | `cb_t3_d1_w2_c3` / `INV_halfOpenBoundedRequests` | 1（脆弱） | 40 步／100000 | 19 | 60.8s |
  | `cb_t2_d2_w3` / `INV_halfOpenFailureRestartsTimer` | 2（脆弱） | 40 步／100000 | 13 | 57.4s |
  | `cb_t2_d3_w4_c1` / `INV_halfOpenClosesAfterSuccessThreshold` | **0** | 60 步／40000 | 17 | 41.2s |

  成因都一樣：這些實例的門檻高（3）或完全沒有併發（`Set(1)`）且 time-out 長（3），
  要走完「湊滿門檻 → 開路 → 期滿 → 試探 → 成功／失敗」需要很長的精確前綴，而
  `healthCheckPass`／`resetState` 在每一步都可能把進度清掉。**這是抽樣深度問題，不是
  模型缺陷**——同一條情境在 `cb_t1_d1_w2`（門檻 1、time-out 1）是 49–372 次。
- 只建模單一 breaker 實例；未建模多 shard／多資源（`source.md`
  §Problems and considerations 的 Resource differentiation）與多區域。
- 未建模 Retry pattern 的組合、manual override、failed-request replay、牆鐘跳躍與
  時鐘漂移（模型用單一邏輯時鐘 `now`；#73 的 `Clock` 注入只是同一個時間來源的測試縫）。

## 如何重跑

```bash
QUINT=/home/runner/work/software_factory/software_factory/node_modules/.bin/quint
cd specs/circuit-breaker
$QUINT typecheck instances.qnt
$QUINT run instances.qnt --main=cb_t1_d1_w2 --invariant=INV_openRequiresThresholdReached \
  --max-steps=24 --max-samples=20000 \
  --witnesses WIT_thresholdOpenedCircuit WIT_closedToOpenTransitionRecorded WIT_trialFailureReopenedCircuit
```

或跑 harness 的集中驗證（與 CI 同一條路徑；`--quint` 省略時預設
`node_modules/.bin/quint`，需在 harness 根目錄執行）：

```bash
cd /home/runner/work/software_factory/software_factory
node dist/cli/factory-spec-verify.js --phase model --spec-name circuit-breaker \
  --target target --summary /tmp/spec-verify.md
```

## Quint 陷阱（前一輪踩到、本輪沿用修正）

`x' = a or b` 會被解析成 `(x' = a) or b`——賦值的優先序比 `or` 高，`or` 的右運算元
變成另一個合取項，`x` 實際上被賦成 `a`。型別檢查不會報錯，只會讓 witness 永遠不可達。
**latch 形式的賦值一律加括號**：`x' = (a or b)`。本輪新增的
`expiredWindowRead' = (expiredWindowRead or failureWindowElapsed)` 已照此寫法。

## 結果判定

結果一律以 CI 依 `verify.yml` 重新執行為準（`traces/` 由 CI 寫入）。以下是 agent 端以
harness `factory-spec-verify`（與 CI 同一條路徑、quint 0.32.0）實測的結果：退出碼 **0**、
`ok=true`、`mismatches=[]`、`advisories=[]`，**21/21 檢查 `holds`、8/8 不變量 `holds`、
零個 0 次 witness**。

| 不變量 | 結果 | 說明 |
| --- | --- | --- |
| `INV_openRejectsOperation` | ✅ 成立（witness 可達） | `shouldBypassOperation` 在 Open 期間一律 `return true`；放行只發生在 Closed 或搶到試探名額時 |
| `INV_closedFailureCountNotExceeded` | ✅ 成立（witness 可達） | 達門檻的那次失敗在同一次 `handleCacheError` 內就 `openCircuit()`；關路路徑一律把計數歸零 |
| `INV_openRequiresThresholdReached` | ✅ 成立（witness 可達） | **上一輪的違反已由不變量改寫消解**（PR #79，人工裁定）：見下節 |
| `INV_closedFailureCounterResetsPeriodically` | ✅ 成立（witness 可達） | 已由 #73 修復：視窗過期後任何讀取都拿到 0（:275-293），邊界也改成含等於（:154） |
| `INV_halfOpenBoundedRequests` | ✅ 成立（witness 可達） | `halfOpenTrialActive` 的 CAS（:188）每個 Open 期間只放行 1 個試探請求（#56） |
| `INV_halfOpenClosesAfterSuccessThreshold` | ✅ 成立（witness 可達） | `successThreshold = 1` 下語意一致（見未決事項 1） |
| `INV_halfOpenFailureReopens` | ✅ 成立（witness 可達） | `handleCacheError` 的 `if (circuitOpen) { openCircuit(); return; }`（:114-120，#56） |
| `INV_halfOpenFailureRestartsTimer` | ✅ 成立（witness 可達） | 同一個 `openCircuit()` 把 `circuitOpenedAt` 設為 `now`（:261） |

### 上一輪的候選發現如何被消解：`INV_openRequiresThresholdReached`

**不是靠改模型消失的**——`CacheErrorHandler` 與模型的程式行為 action 本輪都沒有變更。
上一輪（PR #78）找到的反例被**人工裁定為不變量寫法過強**，人類重跑不變量階段改寫該條
（PR #79），本輪據此在模型維護新的 ghost 變數，反例自然不再存在：

| | 上一輪（PR #78 之前的寫法） | 本輪（PR #79 核准的寫法） |
| --- | --- | --- |
| 形式 | 狀態不變量 `Open implies consecutiveFailures >= failureThreshold` | 轉移性質 `Open implies failuresAtLastOpening >= failureThreshold` |
| 要求 | 整段 Open 期間**計數都**維持在門檻以上 | Closed → Open **轉移當下**的計數達門檻 |
| 結果 | 🔴 四個實例全部違反 | ✅ 四個實例全部成立 |

裁定的依據是引文本身：「The failure threshold **triggers** the Open state only when a
specified number of failures occur during a specified interval.」——講的是**觸發**（轉移），
而程式的失敗計數是**視窗**範圍、Open 是**計時器**範圍，兩個錨點（`firstFailureAt` 與
`circuitOpenedAt`）互不相關，本來就不該要求兩者在整段期間一致。

**上一輪反例描述的現象本身仍然存在，而且仍然值得修**：`openCircuit()`（:259-265）不動
`firstFailureAt`，因此失敗視窗可以在 breaker 還開著時走完，健康報告會出現自相矛盾的
`{"open": true, "consecutiveFailures": 0}`（`CacheHealthIndicator.java:179-180` 與
`OrdersInfoContributor.java:33-34` 把兩者放在同一份報告裡；以程式預設值
`failure-window-ms=60000`、`recovery-timeout-ms=30000`，這個窗口長達 20 秒）。
**它現在的定位是「可觀測性缺陷」，不是本規格任何不變量的違反**——不變量只管
Closed → Open 的轉移條件，而那個條件程式是滿足的。若要修，請另開工單處理報告一致性
（例如 Open 期間回報開路當下的計數），不要動本規格。

**`specs/circuit-breaker/traces/` 下現存四個 ITF 檔是上一輪那個違反的反例，本輪已失效。**
`traces/` 只能由 CI 寫入，本 agent 未觸碰；請由 CI 重新產生／清理。

### witness 的可達性即「非假綠燈」的證據

八條不變量全部成立時，唯一能區分「真的成立」與「情境根本沒發生」的就是 witness 計數。
本輪最後一次 harness 複驗的計數（節錄，完整 21 項見 `verify.yml` 的順序）：

| 不變量 | 實例 | witness | 次數 |
| --- | --- | --- | --- |
| `INV_openRejectsOperation` | `cb_t3_d1_w2_c3` | `WIT_openRejectsArrivingRequest` | 21 |
| `INV_openRequiresThresholdReached` | `cb_t1_d1_w2` | `WIT_thresholdOpenedCircuit` / `WIT_closedToOpenTransitionRecorded` / `WIT_trialFailureReopenedCircuit` | 13759 / 13759 / 53 |
| `INV_openRequiresThresholdReached` | `cb_t3_d1_w2_c3` | `WIT_thresholdOpenedCircuit` / `WIT_closedToOpenTransitionRecorded` | 72 / 72 |
| `INV_halfOpenBoundedRequests` | `cb_t3_d1_w2_c3` | `WIT_halfOpenAdmitsTrial` | 25 |
| `INV_halfOpenClosesAfterSuccessThreshold` | `cb_t2_d3_w4_c1` | `WIT_trialSuccessClosedCircuit` | 17 |
| `INV_halfOpenFailureReopens` | `cb_t3_d1_w2_c3` | `WIT_halfOpenTrialFailed` | 3 |
| `INV_halfOpenFailureRestartsTimer` | `cb_t2_d2_w3` | `WIT_timerRunningAfterTrialFailure` | 21 |

`WIT_trialFailureReopenedCircuit`（本輪新增）特別重要：`INV_openRequiresThresholdReached`
**刻意不涵蓋**「Half-Open 試探失敗立刻重新開路」這條路徑，這條 witness 證明該路徑在抽樣中
確實走到過（53 次），因此不變量的成立不是因為那個分支從未執行。

## 未決事項

1. **`successThreshold` 的語意。** `source.md` 說「after a specified number of successful,
   **consecutive** operation invocations」，程式沒有這個設定：`recordSuccess`（:226-235）
   單次成功即 `closeCircuit()`。Issue #50 指定採最小合法值 1，於是「1 次連續成功」與程式
   一致，`INV_halfOpenClosesAfterSuccessThreshold` 成立。**若人類認為規格意圖是 > 1，
   則這是一個實作缺陷而非規格參數選擇**，需要人工裁定；本階段不擴大解讀。
2. **method 內部的奈秒級交錯不建模。** `shouldBypassOperation` 先讀 `circuitOpenedAt`
   （:185）再 CAS `halfOpenTrialActive`（:188）；兩者之間若有另一執行緒 `openCircuit()`，
   本執行緒可能拿著過期快照通過 CAS，在**新的** Open 期間被放行——這會直接影響
   `INV_openRejectsOperation` 與 `INV_halfOpenBoundedRequests`。本模型以「毫秒級窗口
   （閘門→受保護操作）」為建模邊界，看不到這個交錯。**要不要把建模粒度降到單一 volatile
   讀寫，是成本與保真度的權衡，交人類裁定。**
3. **`failuresAtLastOpening` 在關路時是否該歸零。** 本模型採「不歸零」（逐字符合
   `invariants.qnt:48-51` 的「最近一次 Closed → Open 轉移」）。另一種寫法是關路時歸零，
   兩者在本模型下對結果沒有差異（Closed → Open 的唯一入口是 `failWhileClosed`），但語意
   不同：歸零版本額外斷言「每次進入 Open 都必須有一次記錄在案的達門檻轉移」。
   **若人類希望不變量帶上這層更強的意思，需要重跑不變量階段。**
4. **`consecutiveFailures` 對應到程式的哪個值**（沿用上一輪未決事項，人類已透過 PR #79
   的裁定間接確認本輪選擇可接受）：模型取「任何讀取者實際拿到的值」（視窗過期即 0），
   而非 `AtomicInteger` 欄位的惰性記憶值。詳見上文「失敗計數的兩層表示」。
   **若人類認為該對應到欄位本身，`INV_closedFailureCounterResetsPeriodically` 會重新違反。**
5. **抽樣不是證明。** 全部檢查是 `mode: run`（隨機模擬），本環境無法安裝 Apalache
   （`quint verify` 在 `$HOME/.quint` 解壓時 `EACCES`）。三項稀有 witness 的命中率只有
   0.004%–0.04%，說明抽樣對這些深層情境的覆蓋很稀薄——**「成立」只代表抽樣中未見反例**。
   若要真正的有界窮盡證明，需要人類提供可用的 Apalache 環境。
