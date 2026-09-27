// Circuit Breaker 不變量（ADR-018 不變量階段）
//
// 語意來源：specs/circuit-breaker/source.md（Azure Architecture Center
// "Circuit Breaker pattern" 原文快照）。本檔只描述規格要求，不描述
// CacheErrorHandler 的實作現況；as-is 模型於模型階段另寫在 model.qnt。
//
// 狀態詞彙（僅名稱與型別）取自
// src/main/java/com/sivalabs/bookstore/orders/cache/CacheErrorHandler.java。
module invariants {

  // ---------------------------------------------------------------------------
  // 型別
  // ---------------------------------------------------------------------------

  // Closed／Open／Half-Open 三態（source.md §Solution）。
  type CircuitState = Closed | Open | HalfOpen

  // ---------------------------------------------------------------------------
  // 常數（簽章取自 CacheErrorHandler 的設定值）
  // ---------------------------------------------------------------------------

  // Closed 狀態下觸發 Open 的失敗門檻（failureThreshold）。
  const failureThreshold: int

  // Half-Open 要連續成功幾次才回到 Closed（規格：a specified number of
  // successful, consecutive operation invocations；程式碼無對應設定）。
  const successThreshold: int

  // Open 的 time-out 長度，以邏輯時間單位表示（circuitOpenDuration）。
  const circuitOpenDuration: int

  // Closed 的失敗計數視窗長度（規格：a specified interval；程式碼無對應設定）。
  const failureWindow: int

  // Half-Open 允許放行的請求數上限（規格：A limited number of requests）。
  const maxHalfOpenRequests: int

  // ---------------------------------------------------------------------------
  // 狀態
  // ---------------------------------------------------------------------------

  // 電路是否處於 Open／Half-Open 這條路徑上（對應 circuitOpen；Closed 時為 false）。
  var circuitOpen: bool

  // 電路被打開的邏輯時間；-1 表示從未打開（對應 circuitOpenedAt）。
  var circuitOpenedAt: int

  // 目前邏輯時間（對應 LocalDateTime.now()）。
  var now: int

  // Closed 的近期失敗計數（對應 consecutiveFailures）。
  var consecutiveFailures: int

  // 目前失敗計數視窗的起點（規格的 time-based failure counter）。
  var windowStartedAt: int

  // Half-Open 期間連續成功次數（規格的 success counter）。
  var halfOpenSuccesses: int

  // 目前 Half-Open 期間已放行到受保護操作的請求數。
  var halfOpenAdmitted: int

  // 目前 Half-Open 期間是否已有請求失敗（失敗後電路必須回到 Open）。
  var halfOpenFailed: bool

  // 最近一次 Half-Open 期間失敗的邏輯時間；-1 表示尚未發生。
  var lastHalfOpenFailureAt: int

  // 在 Open 狀態下仍被放行到受保護操作的請求數（安全不變量要求恆為 0）。
  var admittedWhileOpen: int

  // 電路累計被打開的次數（對應 totalCircuitOpenings）。
  var totalCircuitOpenings: int

  // 建議改用 fallback 的次數（對應 fallbackRecommendations）。
  var fallbackRecommendations: int

  // 每個操作的錯誤次數（對應 errorCounts）。
  var errorCounts: str -> int

  // 每個操作最後一次錯誤的邏輯時間（對應 lastErrorTimes）。
  var lastErrorTimes: str -> int

  // ---------------------------------------------------------------------------
  // 衍生狀態
  // ---------------------------------------------------------------------------

  // circuitOpenedAt 的「從未打開」哨兵值。
  pure val neverOpened: int = -1

  // 由 circuitOpen 與 time-out 是否到期推得的三態。
  val circuitState: CircuitState =
    if (not(circuitOpen)) Closed
    else if (circuitOpenedAt >= 0 and now - circuitOpenedAt > circuitOpenDuration) HalfOpen
    else Open

  // ---------------------------------------------------------------------------
  // 不變量
  // ---------------------------------------------------------------------------

// source: source.md §Solution
// 「The request from the application fails immediately and an exception is returned to the application.」
  val INV_openRejectsOperation: bool =
    circuitState == Open implies admittedWhileOpen == 0

// source: source.md §Solution
// 「If the number of recent failures exceeds a specified threshold within a given time period, the proxy is placed into the **Open** state and starts a time-out timer.」
  val INV_closedFailureCountNotExceeded: bool =
    circuitState == Closed implies consecutiveFailures <= failureThreshold

// source: source.md §Solution
// 「The failure threshold triggers the **Open** state only when a specified number of failures occur during a specified interval.」
  val INV_openRequiresExceededThreshold: bool =
    circuitState == Open implies consecutiveFailures > failureThreshold

// source: source.md §Solution
// 「The failure counter for the **Closed** state is time based. It automatically resets at periodic intervals.」
  val INV_closedFailureCounterResetsPeriodically: bool =
    circuitState == Closed and now - windowStartedAt >= failureWindow implies consecutiveFailures == 0

// source: source.md §Solution
// 「**Half-Open:** A limited number of requests from the application are allowed to pass through and invoke the operation.」
  val INV_halfOpenBoundedRequests: bool =
    circuitState == HalfOpen implies halfOpenAdmitted <= maxHalfOpenRequests

// source: source.md §Solution
// 「The circuit breaker reverts to the **Closed** state after a specified number of successful, consecutive operation invocations.」
  val INV_halfOpenClosesAfterSuccessThreshold: bool =
    circuitState == Closed and halfOpenSuccesses > 0 implies halfOpenSuccesses >= successThreshold

// source: source.md §Solution
// 「If any request fails, the circuit breaker assumes that the fault is still present, so it reverts to the **Open** state.」
  val INV_halfOpenFailureReopens: bool =
    halfOpenFailed implies circuitState == Open

// source: source.md §Solution
// 「It restarts the time-out timer so that the system can recover from the failure.」
  val INV_halfOpenFailureRestartsTimer: bool =
    lastHalfOpenFailureAt >= 0 implies circuitOpenedAt >= lastHalfOpenFailureAt
}
