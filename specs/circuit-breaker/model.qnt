// Circuit Breaker as-is 模型（ADR-018 模型階段，2026-09-27 修復後複驗）
//
// 依 src/main/java/com/sivalabs/bookstore/orders/cache/CacheErrorHandler.java 的
// **目前 trunk 現況**建模（已含 Issue #56 的修復：半開失敗重新開路並重新計時、
// 半開只放行一個試探請求、Closed 失敗計數依時間視窗歸零）。不變量沿用已核准的
// invariants.qnt（本檔不重述、不修改）。
//
// 建模範圍（Issue #50）：
//   executeWithFallback／executeVoidOperation（:51-91）、handleCacheError（:93-114）、
//   registerClosedStateFailure（:122-131）、isCircuitOpen（:133-145）、
//   shouldBypassOperation（:155-171）、checkCacheHealth（:173-188）、
//   recordSuccess（:200-209）、resetErrorState（:222-231）、openCircuit（:233-239）、
//   closeCircuit（:241-247）。
//
// 併發抽象（明示，並列於 PR 的「未決事項」）：
//   - THREADS 個呼叫端各自有一個 pc（Idle／Running），可同時有多個請求在飛行中。
//   - **每個 public method 的呼叫視為一個原子步驟**，唯一例外是「閘門放行 → 受保護
//     操作回來」之間的窗口（beginRequest → finishSuccess／failWhile*）：那是真正
//     以毫秒計的窗口（打到 Redis），也是實務上交錯會發生的地方。method 內部相鄰
//     volatile 讀寫之間（例如 shouldBypassOperation 讀 circuitOpenedAt 與 CAS
//     halfOpenTrialActive 之間）的奈秒級窗口**不建模**——見未決事項 1。
//   - admittedWhileOpen 在**請求放行的當下**依當時狀態計數（Issue #50 指定；上一輪
//     在請求結束時計數，把 Closed 放行、執行期間才開路的請求誤算成 Open 放行）。
//
// 輔助變數（規格側，程式無對應欄位）的生命週期：halfOpenAdmitted／halfOpenSuccesses／
// halfOpenFailed／lastHalfOpenFailureAt 都是「本次 Open→Half-Open 情境」範圍的計量，
// 於新的 Open 情境開始（openCircuit）或電路關閉（closeCircuit）時歸零；halfOpenFailed
// 另於 Open 期滿（tick 跨過 circuitOpenDuration）時清掉——該次失敗要求的「回到 Open」
// 已由這段 Open 期間履行完畢。詳見 docs/specs/circuit-breaker-model.md。

module model {
  import invariants.* from "./invariants"
  export invariants.*

  // ---------------------------------------------------------------------------
  // 常數（模型專屬；invariants.qnt 的常數由 instances.qnt 一併綁定）
  // ---------------------------------------------------------------------------

  // 併發呼叫端。CacheErrorHandler 是 @Component 單例，未限制呼叫執行緒數量。
  const THREADS: Set[int]

  // ---------------------------------------------------------------------------
  // 詞彙
  // ---------------------------------------------------------------------------

  // 受保護操作的 operationName（程式接受任意字串，取兩個代表值）。
  pure val REQUEST_OPERATIONS: Set[str] = Set("get", "put")

  // checkCacheHealth 例外時 recordError 用的固定鍵（CacheErrorHandler.java:185）。
  pure val HEALTH_CHECK: str = "health-check"

  // errorCounts／lastErrorTimes 的鍵集合。
  pure val OPERATIONS: Set[str] = REQUEST_OPERATIONS.union(Set(HEALTH_CHECK))

  // 呼叫端的位置：Idle＝不在呼叫中；Running＝已被閘門放行、受保護操作尚未回來。
  type Pc = Idle | Running

  // 呼叫端狀態：trial 表示這個請求是 half-open 的試探請求（搶到 CAS 的那一個）。
  type ThreadState = { pc: Pc, op: str, trial: bool }

  pure val IDLE_THREAD: ThreadState = { pc: Idle, op: "", trial: false }

  // ---------------------------------------------------------------------------
  // 模型專屬狀態
  // ---------------------------------------------------------------------------

  // AtomicBoolean halfOpenTrialActive（CacheErrorHandler.java:27）。
  var halfOpenTrialActive: bool

  // 每個呼叫端的位置與該請求的身分。
  var threads: int -> ThreadState

  // 稽核用：是否確實有請求在 Open 狀態下被閘門擋下走 fallback（witness 用）。
  var rejectedWhileOpen: bool

  // ---------------------------------------------------------------------------
  // shouldBypassOperation()（CacheErrorHandler.java:155-171）
  // ---------------------------------------------------------------------------

  // `if (!circuitOpen) return false;`（:156-158）——Closed 一律放行。
  val gateClosedAdmits: bool = not(circuitOpen)

  // `openedAt != null && Duration.between(openedAt, now) > circuitOpenDuration`（:161）
  // ——recovery timer 已到期；等價於 invariants.qnt 的 circuitState == HalfOpen。
  val gateTimerExpired: bool =
    circuitOpen and circuitOpenedAt >= 0 and now - circuitOpenedAt > circuitOpenDuration

  // `halfOpenTrialActive.compareAndSet(false, true)`（:162）——只有搶到的那一個放行。
  val gateTrialAdmits: bool = gateTimerExpired and not(halfOpenTrialActive)

  // 閘門放行與否；其餘情況 `return true`（:167、:170）＝ bypass。
  val gateAdmits: bool = gateClosedAdmits or gateTrialAdmits

  // ---------------------------------------------------------------------------
  // 「其餘變數不變」的組合積木（Quint 要求每個 var 在每個 action 各賦值一次）
  // ---------------------------------------------------------------------------

  action keepClock: bool = now' = now

  action keepBreaker: bool = all {
    circuitOpen' = circuitOpen,
    circuitOpenedAt' = circuitOpenedAt,
    halfOpenTrialActive' = halfOpenTrialActive,
    totalCircuitOpenings' = totalCircuitOpenings,
  }

  action keepFailureWindow: bool = all {
    consecutiveFailures' = consecutiveFailures,
    windowStartedAt' = windowStartedAt,
  }

  action keepHalfOpenAux: bool = all {
    halfOpenSuccesses' = halfOpenSuccesses,
    halfOpenAdmitted' = halfOpenAdmitted,
    halfOpenFailed' = halfOpenFailed,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
  }

  action keepErrorStats: bool = all {
    errorCounts' = errorCounts,
    lastErrorTimes' = lastErrorTimes,
    fallbackRecommendations' = fallbackRecommendations,
  }

  action keepAudit: bool = all {
    admittedWhileOpen' = admittedWhileOpen,
    rejectedWhileOpen' = rejectedWhileOpen,
  }

  action keepThreads: bool = threads' = threads

  // openCircuit()（:233-239）：開路、重新起算 time-out、釋放試探名額、累計開路次數。
  // 同時讓「本次 Open 情境」的輔助計量歸零。
  action doOpenCircuit: bool = all {
    circuitOpen' = true,
    circuitOpenedAt' = now,
    halfOpenTrialActive' = false,
    totalCircuitOpenings' = totalCircuitOpenings + 1,
    halfOpenAdmitted' = 0,
    halfOpenSuccesses' = 0,
  }

  // ---------------------------------------------------------------------------
  // init
  // ---------------------------------------------------------------------------

  action init: bool = all {
    circuitOpen' = false,
    circuitOpenedAt' = neverOpened,
    now' = 0,
    consecutiveFailures' = 0,
    // firstFailureAt == null（CacheErrorHandler.java:24）。
    windowStartedAt' = neverOpened,
    halfOpenSuccesses' = 0,
    halfOpenAdmitted' = 0,
    halfOpenFailed' = false,
    lastHalfOpenFailureAt' = neverOpened,
    admittedWhileOpen' = 0,
    totalCircuitOpenings' = 0,
    fallbackRecommendations' = 0,
    errorCounts' = OPERATIONS.mapBy(_ => 0),
    lastErrorTimes' = OPERATIONS.mapBy(_ => neverOpened),
    halfOpenTrialActive' = false,
    threads' = THREADS.mapBy(_ => IDLE_THREAD),
    rejectedWhileOpen' = false,
  }

  // ---------------------------------------------------------------------------
  // 時間推進（LocalDateTime.now()）
  // ---------------------------------------------------------------------------

  // 這一刻之後 recovery timer 是否已到期（Open 期滿 → Half-Open 情境）。
  val timerExpiresAfterTick: bool =
    circuitOpen and circuitOpenedAt >= 0 and (now + 1) - circuitOpenedAt > circuitOpenDuration

  action tick: bool = all {
    now' = now + 1,
    // Open 期滿：上一次 Half-Open 失敗所要求的「回到 Open」已履行完畢。
    halfOpenFailed' = if (timerExpiresAfterTick) false else halfOpenFailed,
    halfOpenSuccesses' = halfOpenSuccesses,
    halfOpenAdmitted' = halfOpenAdmitted,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
    keepBreaker,
    keepFailureWindow,
    keepErrorStats,
    keepAudit,
    keepThreads,
  }

  // ---------------------------------------------------------------------------
  // executeWithFallback／executeVoidOperation（:51-91）
  // ---------------------------------------------------------------------------

  // 閘門放行：請求進入受保護操作。circuitOpen 為真時走的是 half-open 試探路徑。
  action beginRequest(t: int, op: str): bool = {
    val trial = circuitOpen
    all {
      threads.get(t).pc == Idle,
      REQUEST_OPERATIONS.contains(op),
      gateAdmits,
      threads' = threads.put(t, { pc: Running, op: op, trial: trial }),
      // compareAndSet(false, true) 成功（:162）。
      halfOpenTrialActive' = trial or halfOpenTrialActive,
      // 放行「當下」的狀態決定計量歸屬（Issue #50）。
      halfOpenAdmitted' = if (circuitState == HalfOpen) halfOpenAdmitted + 1 else halfOpenAdmitted,
      admittedWhileOpen' = if (circuitState == Open) admittedWhileOpen + 1 else admittedWhileOpen,
      rejectedWhileOpen' = rejectedWhileOpen,
      circuitOpen' = circuitOpen,
      circuitOpenedAt' = circuitOpenedAt,
      totalCircuitOpenings' = totalCircuitOpenings,
      halfOpenSuccesses' = halfOpenSuccesses,
      halfOpenFailed' = halfOpenFailed,
      lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
      keepClock,
      keepFailureWindow,
      keepErrorStats,
    }
  }

  // 閘門擋下（:56-61、:75-80）：recordError("Circuit breaker open")＋建議 fallback，
  // 不執行受保護操作，呼叫立刻返回（呼叫端回到 Idle）。
  action rejectRequest(t: int, op: str): bool = all {
    threads.get(t).pc == Idle,
    REQUEST_OPERATIONS.contains(op),
    not(gateAdmits),
    errorCounts' = errorCounts.put(op, errorCounts.get(op) + 1),
    lastErrorTimes' = lastErrorTimes.put(op, now),
    fallbackRecommendations' = fallbackRecommendations + 1,
    rejectedWhileOpen' = rejectedWhileOpen or circuitState == Open,
    admittedWhileOpen' = admittedWhileOpen,
    keepClock,
    keepBreaker,
    keepFailureWindow,
    keepHalfOpenAux,
    keepThreads,
  }

  // ---------------------------------------------------------------------------
  // recordSuccess(operationName)（:200-209）
  // ---------------------------------------------------------------------------

  action finishSuccess(t: int): bool = {
    val th = threads.get(t)
    // `if (circuitOpen) { closeCircuit(); }`（:205-208）。
    val closes = circuitOpen
    all {
      th.pc == Running,
      consecutiveFailures' = 0,
      windowStartedAt' = neverOpened,
      errorCounts' = errorCounts.put(th.op, 0),
      lastErrorTimes' = lastErrorTimes.put(th.op, neverOpened),
      // Half-Open 試探成功才是規格說的 successful consecutive invocation。
      halfOpenSuccesses' = if (th.trial) halfOpenSuccesses + 1 else halfOpenSuccesses,
      circuitOpen' = false,
      circuitOpenedAt' = if (closes) neverOpened else circuitOpenedAt,
      halfOpenTrialActive' = if (closes) false else halfOpenTrialActive,
      halfOpenAdmitted' = if (closes) 0 else halfOpenAdmitted,
      halfOpenFailed' = if (closes) false else halfOpenFailed,
      lastHalfOpenFailureAt' = if (closes) neverOpened else lastHalfOpenFailureAt,
      totalCircuitOpenings' = totalCircuitOpenings,
      fallbackRecommendations' = fallbackRecommendations,
      threads' = threads.put(t, IDLE_THREAD),
      keepClock,
      keepAudit,
    }
  }

  // ---------------------------------------------------------------------------
  // handleCacheError(exception, operationName, key)（:93-114）
  // ---------------------------------------------------------------------------

  // `if (circuitOpen) { openCircuit(); return; }`（:102-108，#56 的修復）：
  // 失敗發生時電路仍在 Open／Half-Open 路徑上 → 立刻重新開路並重新起算 time-out，
  // 不動 Closed 的失敗計數。
  action failWhileOpenPath(t: int): bool = {
    val th = threads.get(t)
    all {
      th.pc == Running,
      circuitOpen,
      errorCounts' = errorCounts.put(th.op, errorCounts.get(th.op) + 1),
      lastErrorTimes' = lastErrorTimes.put(th.op, now),
      fallbackRecommendations' = fallbackRecommendations + 1,
      doOpenCircuit,
      halfOpenFailed' = th.trial or halfOpenFailed,
      lastHalfOpenFailureAt' = if (th.trial) now else lastHalfOpenFailureAt,
      consecutiveFailures' = consecutiveFailures,
      windowStartedAt' = windowStartedAt,
      threads' = threads.put(t, IDLE_THREAD),
      keepClock,
      keepAudit,
    }
  }

  // `int failures = registerClosedStateFailure(); if (failures >= failureThreshold)`
  // （:110-113 ＋ :122-131）：失敗發生時電路是 Closed。時間視窗以 firstFailureAt
  // 為錨點，**只有新的失敗抵達時**才可能重設（`elapsed > failureWindow`）。
  action failWhileClosed(t: int): bool = {
    val th = threads.get(t)
    val windowExpired = windowStartedAt < 0 or now - windowStartedAt > failureWindow
    val failures = if (windowExpired) 1 else consecutiveFailures + 1
    val opens = failures >= failureThreshold
    all {
      th.pc == Running,
      not(circuitOpen),
      errorCounts' = errorCounts.put(th.op, errorCounts.get(th.op) + 1),
      lastErrorTimes' = lastErrorTimes.put(th.op, now),
      fallbackRecommendations' = fallbackRecommendations + 1,
      consecutiveFailures' = failures,
      windowStartedAt' = if (windowExpired) now else windowStartedAt,
      circuitOpen' = opens,
      circuitOpenedAt' = if (opens) now else circuitOpenedAt,
      halfOpenTrialActive' = if (opens) false else halfOpenTrialActive,
      totalCircuitOpenings' = if (opens) totalCircuitOpenings + 1 else totalCircuitOpenings,
      halfOpenAdmitted' = if (opens) 0 else halfOpenAdmitted,
      halfOpenSuccesses' = if (opens) 0 else halfOpenSuccesses,
      halfOpenFailed' = halfOpenFailed,
      lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
      threads' = threads.put(t, IDLE_THREAD),
      keepClock,
      keepAudit,
    }
  }

  // ---------------------------------------------------------------------------
  // checkCacheHealth(healthCheck)（:173-188）
  // ---------------------------------------------------------------------------

  // healthCheck 回 true → closeCircuit()（:175-178）；程式不檢查當下狀態，
  // 即使電路本來就是 Closed 也會把計數與計時器清乾淨。
  action healthCheckPass: bool = all {
    circuitOpen' = false,
    circuitOpenedAt' = neverOpened,
    halfOpenTrialActive' = false,
    consecutiveFailures' = 0,
    windowStartedAt' = neverOpened,
    halfOpenAdmitted' = 0,
    halfOpenFailed' = false,
    lastHalfOpenFailureAt' = neverOpened,
    halfOpenSuccesses' = halfOpenSuccesses,
    totalCircuitOpenings' = totalCircuitOpenings,
    keepClock,
    keepErrorStats,
    keepAudit,
    keepThreads,
  }

  // healthCheck 丟例外 → 只 recordError("health-check")（:183-187）；電路狀態不變。
  // （healthCheck 回 false 只寫 log、不改任何狀態，模型不另設步驟。）
  action healthCheckThrows: bool = all {
    errorCounts' = errorCounts.put(HEALTH_CHECK, errorCounts.get(HEALTH_CHECK) + 1),
    lastErrorTimes' = lastErrorTimes.put(HEALTH_CHECK, now),
    fallbackRecommendations' = fallbackRecommendations,
    keepClock,
    keepBreaker,
    keepFailureWindow,
    keepHalfOpenAux,
    keepAudit,
    keepThreads,
  }

  // ---------------------------------------------------------------------------
  // resetErrorState()（:222-231）；totalCircuitOpenings 不在重設範圍內。
  // ---------------------------------------------------------------------------

  action resetState: bool = all {
    consecutiveFailures' = 0,
    windowStartedAt' = neverOpened,
    circuitOpen' = false,
    circuitOpenedAt' = neverOpened,
    halfOpenTrialActive' = false,
    fallbackRecommendations' = 0,
    errorCounts' = OPERATIONS.mapBy(_ => 0),
    lastErrorTimes' = OPERATIONS.mapBy(_ => neverOpened),
    halfOpenAdmitted' = 0,
    halfOpenSuccesses' = 0,
    halfOpenFailed' = false,
    lastHalfOpenFailureAt' = neverOpened,
    totalCircuitOpenings' = totalCircuitOpenings,
    keepClock,
    keepAudit,
    keepThreads,
  }

  // ---------------------------------------------------------------------------
  // step
  // ---------------------------------------------------------------------------

  action step: bool = {
    nondet t = THREADS.oneOf()
    nondet op = REQUEST_OPERATIONS.oneOf()
    any {
      beginRequest(t, op),
      rejectRequest(t, op),
      finishSuccess(t),
      failWhileOpenPath(t),
      failWhileClosed(t),
      healthCheckPass,
      healthCheckThrows,
      resetState,
      tick,
    }
  }

  // ---------------------------------------------------------------------------
  // 情境 witness（ADR-018 Q34）
  //
  // 每條 INV_* 至少一個：正面敘述「該不變量要保護的情境確實發生」，不得是不變量的
  // 否定（否則不變量成立時必然不可達，正確的不變量會被判成假綠燈），也不得在 init
  // 就成立（那證明不了任何動作真的發生過）。
  // ---------------------------------------------------------------------------

  // INV_openRejectsOperation：電路確實處於 Open，且確實有請求在 Open 期間被擋下
  // 走 fallback（「請求立刻失敗」的情境真的發生過）。
  val WIT_openRejectsArrivingRequest: bool = circuitState == Open and rejectedWhileOpen

  // INV_closedFailureCountNotExceeded：Closed 期間確實累積了近期失敗。
  val WIT_closedAccumulatesFailures: bool = circuitState == Closed and consecutiveFailures > 0

  // INV_openRequiresThresholdReached：電路確實因失敗達門檻而被打開過。
  val WIT_thresholdOpenedCircuit: bool = circuitState == Open and totalCircuitOpenings > 0

  // INV_closedFailureCounterResetsPeriodically：Closed 期間有過失敗，而且自該視窗
  // 起點起算已經整整經過一個計數視窗（時間確實推進到「該自動歸零」的時點）。
  val WIT_failureWindowFullyElapsed: bool =
    circuitState == Closed and windowStartedAt >= 0 and now - windowStartedAt >= failureWindow

  // INV_halfOpenBoundedRequests：Half-Open 期間確實有試探請求被放行到受保護操作。
  val WIT_halfOpenAdmitsTrial: bool = circuitState == HalfOpen and halfOpenAdmitted > 0

  // INV_halfOpenClosesAfterSuccessThreshold：Half-Open 的試探成功，電路回到 Closed。
  val WIT_trialSuccessClosedCircuit: bool = circuitState == Closed and halfOpenSuccesses > 0

  // INV_halfOpenFailureReopens：Half-Open 的試探請求確實失敗過。
  val WIT_halfOpenTrialFailed: bool = halfOpenFailed

  // INV_halfOpenFailureRestartsTimer：Half-Open 失敗後電路重新處於 Open，
  // recovery timer 正在跑。
  val WIT_timerRunningAfterTrialFailure: bool =
    lastHalfOpenFailureAt >= 0 and circuitState == Open
}
