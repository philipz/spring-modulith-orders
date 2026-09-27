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
- 單次檢查實測牆鐘：`holds` 類 6.4–9.1 秒（`--max-steps=24 --max-samples=20000`）、
  違反類 2.4 秒以內；Issue #50 的上限是 600 秒。全 21 項檢查總牆鐘 **151 秒**。
  `verify.yml` 逾時總和 1560 秒（上限 1800）。
- 只建模單一 breaker 實例；未建模多 shard／多資源（`source.md`
  §Problems and considerations 的 Resource differentiation）與多區域。
- 未建模 Retry pattern 的組合、manual override、failed-request replay、牆鐘跳躍與
  時鐘漂移（模型用單一邏輯時鐘 `now`；#73 的 `Clock` 注入只是同一個時間來源的測試縫）。

## 如何重跑

```bash
QUINT=/home/runner/work/software_factory/software_factory/node_modules/.bin/quint
cd specs/circuit-breaker
$QUINT typecheck instances.qnt
$QUINT run instances.qnt --main=cb_t2_d3_w4_c1 --invariant=INV_openRequiresThresholdReached \
  --max-steps=24 --max-samples=20000 --witnesses WIT_thresholdOpenedCircuit
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
`ok=true`、`mismatches=[]`，全 21 項檢查總牆鐘 **151 秒**。

| 不變量 | 結果 | 說明 |
| --- | --- | --- |
| `INV_openRejectsOperation` | ✅ 成立（witness 可達） | `shouldBypassOperation` 在 Open 期間一律 `return true`；放行只發生在 Closed 或搶到試探名額時 |
| `INV_closedFailureCountNotExceeded` | ✅ 成立（witness 可達） | 達門檻的那次失敗在同一次 `handleCacheError` 內就 `openCircuit()`；關路路徑一律把計數歸零 |
| `INV_openRequiresThresholdReached` | 🔴 違反（候選發現，未回放） | 見下節——**本輪新出現**，是 #73 讀取語意的直接後果 |
| `INV_closedFailureCounterResetsPeriodically` | ✅ 成立（witness 可達） | **上一輪的違反已由 #73 修復**：視窗過期後任何讀取都拿到 0（:275-293），邊界也改成含等於（:154） |
| `INV_halfOpenBoundedRequests` | ✅ 成立（witness 可達） | `halfOpenTrialActive` 的 CAS（:188）每個 Open 期間只放行 1 個試探請求（#56） |
| `INV_halfOpenClosesAfterSuccessThreshold` | ✅ 成立（witness 可達） | `successThreshold = 1` 下語意一致（見未決事項） |
| `INV_halfOpenFailureReopens` | ✅ 成立（witness 可達） | `handleCacheError` 的 `if (circuitOpen) { openCircuit(); return; }`（:114-120，#56） |
| `INV_halfOpenFailureRestartsTimer` | ✅ 成立（witness 可達） | 同一個 `openCircuit()` 把 `circuitOpenedAt` 設為 `now`（:261） |

### 候選發現：`INV_openRequiresThresholdReached`（本輪新出現）

`source.md` §Solution：「The failure threshold triggers the **Open** state only when a
specified number of failures occur during a specified interval.」——已核准的不變量把它寫成
狀態不變量 `circuitState == Open implies consecutiveFailures >= failureThreshold`
（門檻語意由人工審查在 PR #52 裁定）。

**成因**：失敗計數的視窗以 `firstFailureAt` 為錨點，Open 狀態的存續則以 `circuitOpenedAt`
為錨點，兩者互不相關；`openCircuit()`（:259-265）**不動** `firstFailureAt`。#73 之後，
只要失敗視窗在 breaker 還開著的期間走完，讀取者拿到的計數就變成 0，於是出現
「breaker 是 Open，但回報的 `consecutiveFailures` 是 0」。這不是抽象假象：
`CacheHealthIndicator.java:179-180` 與 `OrdersInfoContributor.java:33-34` 正好把
`isCircuitOpen()` 與 `getConsecutiveFailureCount()` 放在同一份報告裡，運維看到的會是
自相矛盾的 `{"open": true, "consecutiveFailures": 0}`。

反例有兩條互不相同的路徑，四個實例全部找到（都在 2.4 秒內）：

1. **視窗在 Open 期間走完，不需要任何讀取**（`cb_t2_d3_w4_c1`，**單一執行緒**，
   `failureThreshold=2`、`circuitOpenDuration=3`、`failureWindow=4`）：
   `now=1` 一次失敗 → 計數 1、視窗錨點 1；`now=4` 第二次失敗（`4-1=3 < 4` 仍屬同一視窗）
   → 計數 2 達門檻 → 開路於 `now=4`；`now=5` 只是時間推進 → `5-1=4 >= 4` 視窗走完 →
   讀到的計數 **0**，而 breaker 仍是 Open（`5-4=1 <= 3`）。**與併發交錯無關。**
2. **讀取把歸零寫回欄位後，半開試探失敗重新開路**（`cb_t1_d1_w2`，
   `failureThreshold=1`、`circuitOpenDuration=1`、`failureWindow=2`）：
   `now=2` 失敗即開路（計數 1、視窗錨點 2）→ `now=4` 視窗走完且進入 Half-Open →
   一次 `getConsecutiveFailureCount()` 把欄位與錨點一起清成 0／null（:287-293）→
   半開試探請求失敗 → `handleCacheError` 走 `if (circuitOpen)` 分支重新開路（:114-120），
   **不重新計數** → Open 而計數 0。

**以程式預設值也會發生**：`failure-window-ms=60000`、`recovery-timeout-ms=30000`——
失敗分散在 0–50 秒內湊滿 5 次而在 50 秒開路，60 秒時視窗走完，但 breaker 要到 80 秒才
進入 Half-Open；這 20 秒內健康報告就是 `open: true, consecutiveFailures: 0`。

**這是候選發現（未回放）**：請開 `agent-fix-bug` 工單，由 01-test 的紅燈測試回放到真實
程式確認（ADR-018 Q31）。本工作項不修改 `src/`，也未修改模型讓反例消失。

> **另一種解讀（交人類裁定，未決事項 1）**：規格原文講的是「門檻**觸發** Open 狀態」
> ——那是**轉移**條件，程式完全滿足（`failWhileClosed` 只在 `failures >= failureThreshold`
> 時開路；`failWhileOpenPath` 只讓**已經開著**的 breaker 重新計時）。把它寫成狀態不變量
> 才要求計數在整段 Open 期間都維持在門檻之上，而程式的計數是視窗範圍、Open 是計時器
> 範圍。若人工裁定「狀態不變量的寫法過強」，正確的處理是修正 `invariants.qnt`
> （需重跑不變量階段核准），不是改模型——本階段不得修改 `invariants.qnt`。
