// Circuit Breaker as-is 模型（ADR-018 模型階段）
//
// 依 src/main/java/com/sivalabs/bookstore/orders/cache/CacheErrorHandler.java 的
// 現況建模，包含缺陷；不變量沿用已核准的 invariants.qnt（本檔不重述、不修改）。
//
// 建模範圍（Issue #50 範圍）：
//   executeWithFallback／executeVoidOperation、handleCacheError、isCircuitOpen
//   （時間推進）、checkCacheHealth、recordSuccess、resetErrorState。
//
// 併發抽象：
//   - 每個動作是一個非確定性的原子步驟，模型探索任意交錯（等同多執行緒）。
//   - inFlightOp 另外追蹤「已通過 isCircuitOpen() 檢查、尚未執行 operation」的
//     一個請求，用來表示 isCircuitOpen() 與 operation 執行之間的 check-then-act
//     窗口：期間其他請求可以讓電路開啟，使該請求在 Open 狀態下仍被執行。

module model {
  import invariants.* from "./invariants"
  export invariants.*

  // 快取操作名稱（程式的 operationName 可為任意字串，這裡取兩種代表）。
  pure val REQUEST_OPERATIONS: Set[str] = Set("get", "put")

  // errorCounts／lastErrorTimes 的鍵集合（含 checkCacheHealth 的 "health-check"）。
  pure val OPERATIONS: Set[str] = Set("get", "put", "health-check")

  // isCircuitOpen() 是否放行（CacheErrorHandler.java:99-111）：
  //   Closed 一定放行；Open 只有在 circuitOpenedAt 起算超過 circuitOpenDuration
  //   之後才放行（程式此時仍讓 circuitOpen 保持 true，並未真正切到 Half-Open 欄位）。
  pure def admits(open: bool, openedAt: int, t: int, duration: int): bool =
    not(open) or (openedAt >= 0 and t - openedAt > duration)

  // 追蹤中的請求："" 表示沒有；否則為已通過 isCircuitOpen() 檢查的 operationName。
  var inFlightOp: str

  action init: bool = all {
    circuitOpen' = false,
    circuitOpenedAt' = neverOpened,
    now' = 0,
    consecutiveFailures' = 0,
    windowStartedAt' = 0,
    halfOpenSuccesses' = 0,
    halfOpenAdmitted' = 0,
    halfOpenFailed' = false,
    lastHalfOpenFailureAt' = neverOpened,
    admittedWhileOpen' = 0,
    totalCircuitOpenings' = 0,
    fallbackRecommendations' = 0,
    errorCounts' = OPERATIONS.mapBy(_ => 0),
    lastErrorTimes' = OPERATIONS.mapBy(_ => neverOpened),
    inFlightOp' = "",
  }

  // 邏輯時鐘推進（程式以 LocalDateTime.now() 讀取）。
  action tick: bool = all {
    now' = now + 1,
    circuitOpen' = circuitOpen,
    circuitOpenedAt' = circuitOpenedAt,
    consecutiveFailures' = consecutiveFailures,
    windowStartedAt' = windowStartedAt,
    halfOpenSuccesses' = halfOpenSuccesses,
    halfOpenAdmitted' = halfOpenAdmitted,
    halfOpenFailed' = halfOpenFailed,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
    admittedWhileOpen' = admittedWhileOpen,
    totalCircuitOpenings' = totalCircuitOpenings,
    fallbackRecommendations' = fallbackRecommendations,
    errorCounts' = errorCounts,
    lastErrorTimes' = lastErrorTimes,
    inFlightOp' = inFlightOp,
  }

  // executeWithFallback／executeVoidOperation：通過 isCircuitOpen() 檢查、尚未執行。
  action beginRequest(op: str): bool = all {
    inFlightOp == "",
    REQUEST_OPERATIONS.contains(op),
    admits(circuitOpen, circuitOpenedAt, now, circuitOpenDuration),
    inFlightOp' = op,
    halfOpenAdmitted' = if (circuitState == HalfOpen) halfOpenAdmitted + 1 else halfOpenAdmitted,
    circuitOpen' = circuitOpen,
    circuitOpenedAt' = circuitOpenedAt,
    now' = now,
    consecutiveFailures' = consecutiveFailures,
    windowStartedAt' = windowStartedAt,
    halfOpenSuccesses' = halfOpenSuccesses,
    halfOpenFailed' = halfOpenFailed,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
    admittedWhileOpen' = admittedWhileOpen,
    totalCircuitOpenings' = totalCircuitOpenings,
    fallbackRecommendations' = fallbackRecommendations,
    errorCounts' = errorCounts,
    lastErrorTimes' = lastErrorTimes,
  }

  // 追蹤中的請求：operation 成功（recordSuccess，CacheErrorHandler.java:140-148）。
  action finishSuccess: bool = {
    val op = inFlightOp
    all {
      inFlightOp != "",
      consecutiveFailures' = 0,
      errorCounts' = errorCounts.put(op, 0),
      lastErrorTimes' = lastErrorTimes.put(op, neverOpened),
      circuitOpen' = false,
      circuitOpenedAt' = neverOpened,
      halfOpenSuccesses' = if (circuitState == HalfOpen) halfOpenSuccesses + 1 else halfOpenSuccesses,
      admittedWhileOpen' = if (circuitState == Open) admittedWhileOpen + 1 else admittedWhileOpen,
      inFlightOp' = "",
      now' = now,
      windowStartedAt' = windowStartedAt,
      halfOpenAdmitted' = halfOpenAdmitted,
      halfOpenFailed' = halfOpenFailed,
      lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
      totalCircuitOpenings' = totalCircuitOpenings,
      fallbackRecommendations' = fallbackRecommendations,
    }
  }

  // 追蹤中的請求：operation 失敗（handleCacheError，CacheErrorHandler.java:84-97）。
  action finishFailure: bool = {
    val op = inFlightOp
    val nf = consecutiveFailures + 1
    all {
      inFlightOp != "",
      errorCounts' = errorCounts.put(op, errorCounts.get(op) + 1),
      lastErrorTimes' = lastErrorTimes.put(op, now),
      fallbackRecommendations' = fallbackRecommendations + 1,
      consecutiveFailures' = nf,
      circuitOpen' = if (nf >= failureThreshold and not(circuitOpen)) true else circuitOpen,
      circuitOpenedAt' = if (nf >= failureThreshold and not(circuitOpen)) now else circuitOpenedAt,
      totalCircuitOpenings' = if (nf >= failureThreshold and not(circuitOpen)) totalCircuitOpenings + 1 else totalCircuitOpenings,
      halfOpenFailed' = if (circuitState == HalfOpen) true else halfOpenFailed,
      lastHalfOpenFailureAt' = if (circuitState == HalfOpen) now else lastHalfOpenFailureAt,
      admittedWhileOpen' = if (circuitState == Open) admittedWhileOpen + 1 else admittedWhileOpen,
      inFlightOp' = "",
      now' = now,
      windowStartedAt' = windowStartedAt,
      halfOpenSuccesses' = halfOpenSuccesses,
      halfOpenAdmitted' = halfOpenAdmitted,
    }
  }

  // 原子請求（檢查與執行同一交錯步驟）：成功。
  action requestSuccess(op: str): bool = all {
    REQUEST_OPERATIONS.contains(op),
    admits(circuitOpen, circuitOpenedAt, now, circuitOpenDuration),
    consecutiveFailures' = 0,
    errorCounts' = errorCounts.put(op, 0),
    lastErrorTimes' = lastErrorTimes.put(op, neverOpened),
    circuitOpen' = false,
    circuitOpenedAt' = neverOpened,
    halfOpenSuccesses' = if (circuitState == HalfOpen) halfOpenSuccesses + 1 else halfOpenSuccesses,
    halfOpenAdmitted' = if (circuitState == HalfOpen) halfOpenAdmitted + 1 else halfOpenAdmitted,
    admittedWhileOpen' = admittedWhileOpen,
    now' = now,
    windowStartedAt' = windowStartedAt,
    halfOpenFailed' = halfOpenFailed,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
    totalCircuitOpenings' = totalCircuitOpenings,
    fallbackRecommendations' = fallbackRecommendations,
    inFlightOp' = inFlightOp,
  }

  // 原子請求：失敗（handleCacheError 的門檻與開路邏輯）。
  action requestFailure(op: str): bool = {
    val nf = consecutiveFailures + 1
    all {
      REQUEST_OPERATIONS.contains(op),
      admits(circuitOpen, circuitOpenedAt, now, circuitOpenDuration),
      errorCounts' = errorCounts.put(op, errorCounts.get(op) + 1),
      lastErrorTimes' = lastErrorTimes.put(op, now),
      fallbackRecommendations' = fallbackRecommendations + 1,
      consecutiveFailures' = nf,
      circuitOpen' = if (nf >= failureThreshold and not(circuitOpen)) true else circuitOpen,
      circuitOpenedAt' = if (nf >= failureThreshold and not(circuitOpen)) now else circuitOpenedAt,
      totalCircuitOpenings' = if (nf >= failureThreshold and not(circuitOpen)) totalCircuitOpenings + 1 else totalCircuitOpenings,
      halfOpenAdmitted' = if (circuitState == HalfOpen) halfOpenAdmitted + 1 else halfOpenAdmitted,
      halfOpenFailed' = if (circuitState == HalfOpen) true else halfOpenFailed,
      lastHalfOpenFailureAt' = if (circuitState == HalfOpen) now else lastHalfOpenFailureAt,
      admittedWhileOpen' = admittedWhileOpen,
      now' = now,
      windowStartedAt' = windowStartedAt,
      halfOpenSuccesses' = halfOpenSuccesses,
      inFlightOp' = inFlightOp,
    }
  }

  // executeWithFallback／executeVoidOperation：isCircuitOpen() 為 true → 直接回退，
  // 只 recordError 與 incrementFallbackRecommendation，不執行 operation。
  action requestRejected(op: str): bool = all {
    REQUEST_OPERATIONS.contains(op),
    not(admits(circuitOpen, circuitOpenedAt, now, circuitOpenDuration)),
    errorCounts' = errorCounts.put(op, errorCounts.get(op) + 1),
    lastErrorTimes' = lastErrorTimes.put(op, now),
    fallbackRecommendations' = fallbackRecommendations + 1,
    circuitOpen' = circuitOpen,
    circuitOpenedAt' = circuitOpenedAt,
    now' = now,
    consecutiveFailures' = consecutiveFailures,
    windowStartedAt' = windowStartedAt,
    halfOpenSuccesses' = halfOpenSuccesses,
    halfOpenAdmitted' = halfOpenAdmitted,
    halfOpenFailed' = halfOpenFailed,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
    admittedWhileOpen' = admittedWhileOpen,
    totalCircuitOpenings' = totalCircuitOpenings,
    inFlightOp' = inFlightOp,
  }

  // checkCacheHealth：healthCheck 回 true → closeCircuit（CacheErrorHandler.java:113-122）。
  action checkHealthPass: bool = all {
    circuitOpen' = false,
    consecutiveFailures' = 0,
    circuitOpenedAt' = neverOpened,
    now' = now,
    windowStartedAt' = windowStartedAt,
    halfOpenSuccesses' = halfOpenSuccesses,
    halfOpenAdmitted' = halfOpenAdmitted,
    halfOpenFailed' = halfOpenFailed,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
    admittedWhileOpen' = admittedWhileOpen,
    totalCircuitOpenings' = totalCircuitOpenings,
    fallbackRecommendations' = fallbackRecommendations,
    errorCounts' = errorCounts,
    lastErrorTimes' = lastErrorTimes,
    inFlightOp' = inFlightOp,
  }

  // checkCacheHealth：healthCheck 丟例外 → 只 recordError("health-check")。
  action checkHealthThrows: bool = all {
    errorCounts' = errorCounts.put("health-check", errorCounts.get("health-check") + 1),
    lastErrorTimes' = lastErrorTimes.put("health-check", now),
    circuitOpen' = circuitOpen,
    circuitOpenedAt' = circuitOpenedAt,
    now' = now,
    consecutiveFailures' = consecutiveFailures,
    windowStartedAt' = windowStartedAt,
    halfOpenSuccesses' = halfOpenSuccesses,
    halfOpenAdmitted' = halfOpenAdmitted,
    halfOpenFailed' = halfOpenFailed,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
    admittedWhileOpen' = admittedWhileOpen,
    totalCircuitOpenings' = totalCircuitOpenings,
    fallbackRecommendations' = fallbackRecommendations,
    inFlightOp' = inFlightOp,
  }

  // resetErrorState（CacheErrorHandler.java:161-168）。
  action resetErrorState: bool = all {
    consecutiveFailures' = 0,
    circuitOpen' = false,
    circuitOpenedAt' = neverOpened,
    fallbackRecommendations' = 0,
    errorCounts' = OPERATIONS.mapBy(_ => 0),
    lastErrorTimes' = OPERATIONS.mapBy(_ => neverOpened),
    now' = now,
    windowStartedAt' = windowStartedAt,
    halfOpenSuccesses' = halfOpenSuccesses,
    halfOpenAdmitted' = halfOpenAdmitted,
    halfOpenFailed' = halfOpenFailed,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
    admittedWhileOpen' = admittedWhileOpen,
    totalCircuitOpenings' = totalCircuitOpenings,
    inFlightOp' = inFlightOp,
  }

  action step: bool = {
    nondet op = REQUEST_OPERATIONS.oneOf()
    any {
      beginRequest(op),
      finishSuccess,
      finishFailure,
      requestSuccess(op),
      requestFailure(op),
      requestRejected(op),
      checkHealthPass,
      checkHealthThrows,
      resetErrorState,
      tick,
    }
  }

  // ---------------------------------------------------------------------------
  // 情境 witness（Q34）：正面描述每條不變量要保護的情境確實發生；不得在 init 成立。
  // ---------------------------------------------------------------------------

  // INV_openRejectsOperation：電路已進入 Open，請求應被立即拒絕。
  val WIT_openShortCircuits: bool = circuitState == Open

  // INV_closedFailureCountNotExceeded：Closed 期間已累積近期失敗。
  val WIT_closedWithFailures: bool = circuitState == Closed and consecutiveFailures > 0

  // INV_openRequiresThresholdReached：電路確實因達門檻而被打開過。
  val WIT_circuitOpenedByFailures: bool = totalCircuitOpenings > 0

  // INV_closedFailureCounterResetsPeriodically：Closed 期間失敗且已超過一個計數視窗。
  val WIT_failureWindowElapsed: bool =
    circuitState == Closed and consecutiveFailures > 0 and now - windowStartedAt >= failureWindow

  // INV_halfOpenBoundedRequests：Half-Open 期間已有請求被放行到受保護操作。
  val WIT_halfOpenAdmitsRequest: bool = circuitState == HalfOpen and halfOpenAdmitted > 0

  // INV_halfOpenClosesAfterSuccessThreshold：Half-Open 的成功讓電路回到 Closed。
  val WIT_closedAfterHalfOpenSuccess: bool = circuitState == Closed and halfOpenSuccesses > 0

  // INV_halfOpenFailureReopens：Half-Open 期間有請求失敗。
  val WIT_halfOpenRequestFails: bool = halfOpenFailed

  // INV_halfOpenFailureRestartsTimer：Half-Open 失敗後電路仍處於開啟（計時器議題）。
  val WIT_halfOpenFailureKeepsCircuit: bool = halfOpenFailed and circuitOpen
}
