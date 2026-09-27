# Circuit Breaker as-is 模型紀錄（specs/circuit-breaker）

> ADR-018 模型階段。不變量出自 `specs/circuit-breaker/source.md`（已核准凍結）；
> 本模型依 `CacheErrorHandler` 程式現況建模，**包含缺陷**。本文件由模型階段產出，
> 供審查者理解模型範圍與反例。

## 建模對象

`src/main/java/com/sivalabs/bookstore/orders/cache/CacheErrorHandler.java` 的
`executeWithFallback`、`executeVoidOperation`、`handleCacheError`、`isCircuitOpen`、
`checkCacheHealth`、`recordSuccess`、`resetErrorState`。

（`shouldFallbackToDatabase`、`getCacheErrorStats` 為觀測/統計，無不變量涵蓋，未建模。）

## 檔案

| 檔案 | 內容 |
| --- | --- |
| `invariants.qnt` | 已核准的不變量與狀態詞彙（本階段不修改） |
| `model.qnt` | as-is 行為、`step`、情境 witness `WIT_*` |
| `instances.qnt` | 三組具體常數實例 |
| `verify.yml` | 實例 × 不變量 × 步數 × 逾時 × witness（不宣告預期結果） |
| `traces/` | CI 執行時寫入的反例 ITF（agent 不寫入） |

`model.qnt` 以 `import invariants.* from "./invariants"` 與
`export invariants.*` 為 `module model` 的前兩道敘述（Quint 0.32.0 要求檔案必須以
`module` 起始，故 import/export 位於模組內、而非檔案第一行；這與 harness
`factory-spec-verify` 測試 fixture 及 Redlock 試點的寫法一致）。缺 `export` 會使
`instances.qnt` 看不到 `INV_*`（`QNT404`）。

## 抽象與建模假設

- **單一邏輯時鐘** `now`：`circuitOpenDuration`／`failureWindow` 以邏輯時間單位表示，
  不建模牆鐘跳躍與時鐘漂移。
- **併發＝非確定性交錯的原子步驟**：每個請求是一個原子步驟，模型探索任意交錯。
  另以 `inFlightOp` 追蹤「已通過 `isCircuitOpen()` 檢查、尚未執行 operation」的一個
  請求，表示檢查與執行之間的 check-then-act 窗口（程式對這兩件事沒有鎖或原子性）。
- **`windowStartedAt` 固定為 0**：程式沒有 time-based 失敗計數重設機制，依 Issue #50
  「程式沒有對應機制時照實建模，不得替程式補上重設」，模型不重設它。
- **`successThreshold = 1`、`maxHalfOpenRequests = 1`**：程式無對應設定，依 Issue #50
  採規格最小合法值。
- **`halfOpenAdmitted`／`halfOpenSuccesses`／`halfOpenFailed`** 是規格層觀測量
  （程式沒有這些欄位）；程式沒有 half-open 進入/離開的簿記，故模型不對它們做
  「進入 Half-Open 時重設」的補強。
- `errorCounts`／`lastErrorTimes` 照程式更新，但沒有不變量依賴它們。

## 常數範圍（Q21）

| 常數 | 值 | 依據 |
| --- | --- | --- |
| `failureThreshold` | 1、2、3 | `CacheErrorHandler.java:31` `@Value` 未限制；涵蓋邊界（1）與奇偶 |
| `circuitOpenDuration` | 1、2 | `CacheErrorHandler.java:32` `@Value` 未限制；涵蓋邊界（1）與偶數 |
| `failureWindow` | 2、3 | 程式無對應設定；Issue #50 指定固定視窗，涵蓋奇偶 |
| `successThreshold` | 1 | 程式無對應設定；Issue #50 採規格最小合法值 |
| `maxHalfOpenRequests` | 1 | 程式無對應設定；Issue #50 採規格最小合法值 |

未使用任何程式本身沒有的 `assume`／`assert` 來縮小範圍。

## CI 判定結果（`mode: run` 為隨機抽樣，非證明）

本模型以 harness `factory-spec-verify`（與 CI 同一條路徑）實測，退出碼 0、
`mismatches` 為空、共 5 條**候選發現（未回放）**、3 條成立且 witness 可達。
實際結果一律以 CI 重跑 `verify.yml` 為準；反例 ITF 由 CI 寫入 `traces/`。

| 不變量 | 結果 | 反例／說明 |
| --- | --- | --- |
| `INV_openRejectsOperation` | 🔴 違反 | check-then-act 競態：請求通過 `isCircuitOpen()` 後、執行 operation 前，另一請求開路，該請求仍在 Open 狀態下被執行（`admittedWhileOpen > 0`） |
| `INV_closedFailureCounterResetsPeriodically` | 🔴 違反 | Closed 的失敗計數沒有時窗重設；`consecutiveFailures` 只被成功/關路/`resetErrorState` 歸零 |
| `INV_halfOpenBoundedRequests` | 🔴 違反 | time-out 到期後 `isCircuitOpen()` 對所有請求回 false，Half-Open 沒有放行上限 |
| `INV_halfOpenFailureReopens` | 🔴 違反 | Half-Open 失敗時 `circuitOpen` 仍為 true，`handleCacheError` 的 `!circuitOpen` 條件不成立，故不呼叫 `openCircuit()`，狀態停在 Half-Open |
| `INV_halfOpenFailureRestartsTimer` | 🔴 違反 | 同上根因：`circuitOpenedAt` 未重設，time-out 計時器沒有重新起算 |
| `INV_closedFailureCountNotExceeded` | ✅ 成立 | 門檻在 `handleCacheError` 一達標即開路；Closed 時 `consecutiveFailures < failureThreshold` |
| `INV_openRequiresThresholdReached` | ✅ 成立 | `openCircuit()` 只在 `failures >= failureThreshold` 時呼叫 |
| `INV_halfOpenClosesAfterSuccessThreshold` | ✅ 成立 | `recordSuccess` 在 `circuitOpen` 時關路；`successThreshold = 1` 下語意一致 |

上述違反皆為**候選發現**，未經真實程式回放；請開 `agent-fix-bug` 工單，由紅燈測試
回放確認（ADR-018 Q31）。

## 如何重跑

```bash
QUINT=/home/runner/work/software_factory/software_factory/node_modules/.bin/quint
cd specs/circuit-breaker
$QUINT typecheck instances.qnt
$QUINT run instances.qnt --main=cb_t1_d1_w2 --invariant=INV_openRejectsOperation \
  --max-steps=16 --max-samples=10000 --witnesses WIT_openShortCircuits
```

或跑 harness 的集中驗證（等同 CI）：

```bash
node /home/runner/work/software_factory/software_factory/dist/cli/factory-spec-verify.js \
  --phase model --spec-name circuit-breaker --target target --quint "$QUINT"
```

## 已知限制

- `mode: run` 是隨機抽樣，不保證窮盡；成立只代表抽樣中未見反例。
- 只建模單一 breaker 實例；未建模多 shard／多資源（source.md
  §Problems and considerations 的 Resource differentiation）與多區域。
- 未建模 Retry pattern 的組合、manual override、failed-request replay。
- check-then-act 競態以一個追蹤中的請求表示，是存在性抽象，不枚舉所有並行度。
