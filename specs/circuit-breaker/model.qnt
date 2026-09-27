// Circuit Breaker as-is 模型（ADR-018 模型階段，2026-09-27 不變量重做後複驗）
//
// 本輪的唯一變更來源是**不變量側**（PR #79，人工裁定）：
//   `INV_openRequiresThresholdReached` 由狀態不變量改為**轉移性質**，並為此在
//   invariants.qnt 新增 `var failuresAtLastOpening`（最近一次 Closed → Open 轉移當下的
//   失敗計數）。程式碼沒有對應欄位，它是規格側的輔助（ghost）變數，由本模型維護：
//     - `failWhileClosed` 開路時（`opens`）寫入該次 `registerClosedStateFailure()` 的回傳值
//       （CacheErrorHandler.java:122-125）——這就是 Closed → Open 轉移當下的失敗數。
//     - `failWhileOpenPath`（:114-120 的 Half-Open 試探失敗重新開路）**不更新**：依
//       invariants.qnt 的宣告與 source.md「enters the Open state immediately」，該路徑
//       不受門檻限制。
//     - 其餘步驟（含關路／重設）一律不動：變數語意是「最近一次 Closed → Open 轉移」的
//       歷史紀錄，關路不會讓那次轉移沒發生過。見未決事項 3。
//   程式行為的建模**逐字沿用上一輪（PR #78）**，未因不變量改寫而調整任何一個 action。
//
// 依 src/main/java/com/sivalabs/bookstore/orders/cache/CacheErrorHandler.java 的
// **目前 trunk 現況**建模，已含兩輪修復：
//   - Issue #56：半開失敗立刻重新開路並重新起算 time-out（:114-120）、半開只放行
//     一個試探請求（halfOpenTrialActive CAS，:188）。
//   - Issue #73：時間來源改為可注入的 Clock（:23、:48-53）；失敗計數視窗比較改為
//     「大於或等於」（hasFailureWindowElapsed，:153-155）；讀取計數時若視窗已過期
//     即回傳 0（getConsecutiveFailureCount → expireElapsedFailureWindow，:275-293）。
// 不變量沿用已核准的 invariants.qnt（本檔不重述、不修改）。
//
// 建模範圍（Issue #50）：
//   executeWithFallback（:63-84）、executeVoidOperation（:86-103）、
//   handleCacheError（:105-126）、registerClosedStateFailure（:137-146）、
//   hasFailureWindowElapsed（:153-155）、isCircuitOpen（:157-170）、
//   shouldBypassOperation（:180-197）、checkCacheHealth（:199-214）、
//   recordSuccess（:226-235）、resetErrorState（:248-257）、openCircuit（:259-265）、
//   closeCircuit（:267-273）、getConsecutiveFailureCount（:275-278）＋
//   expireElapsedFailureWindow（:287-293）。
//
// 併發抽象（明示，並列於 PR 的「未決事項」）：
//   - THREADS 個呼叫端各自有一個 pc（Idle／Running），可同時有多個請求在飛行中。
//   - **每個 public method 的呼叫視為一個原子步驟**，唯一例外是「閘門放行 → 受保護
//     操作回來」之間的窗口（beginRequest → finishSuccess／failWhile*）：那是真正
//     以毫秒計的窗口（打到 Redis），也是實務上交錯會發生的地方。method 內部相鄰
//     volatile 讀寫之間（例如 shouldBypassOperation 讀 circuitOpenedAt 與 CAS
//     halfOpenTrialActive 之間）的奈秒級窗口**不建模**——見未決事項 1。
//   - admittedWhileOpen 在**請求放行的當下**依當時狀態計數（Issue #50 指定）。
//
// 失敗計數的兩層表示（#73 的核心語意，見未決事項 2）：
//   - memoFailureCount ≙ AtomicInteger consecutiveFailures 這個**欄位**（:25）。
//     它的歸零是惰性的：只有下一次失敗抵達（registerClosedStateFailure，:140-144）、
//     一次讀取（expireElapsedFailureWindow，:287-293）或關路／重設才會materialize。
//   - consecutiveFailures（invariants.qnt 的詞彙）≙ **任何讀取者實際拿到的值**。
//     程式裡讀到這個計數的每一條路徑都會先套用視窗過期：對外只有
//     getConsecutiveFailureCount()（:275-278，CacheHealthIndicator.java:180、
//     OrdersInfoContributor.java:34 兩個讀取者），對內只有 registerClosedStateFailure
//     （:140，視窗已過期時不是 +1 而是重設為 1）。因此 memoFailureCount 的舊值
//     **沒有任何觀察者、也沒有任何判斷**看得到，等價於一個 memoization 快取。
//   兩者都保留在狀態裡，反例的 ITF 會同時顯示，人工審查可自行比對。
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

  // checkCacheHealth 例外時 recordError 用的固定鍵（CacheErrorHandler.java:211）。
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

  // AtomicBoolean halfOpenTrialActive（CacheErrorHandler.java:29）。
  var halfOpenTrialActive: bool

  // AtomicInteger consecutiveFailures 這個欄位的**當前記憶值**（:25）。
  // 對外可見的計數是 consecutiveFailures（invariants.qnt），見檔頭說明。
  var memoFailureCount: int

  // 每個呼叫端的位置與該請求的身分。
  var threads: int -> ThreadState

  // 稽核用：是否確實有請求在 Open 狀態下被閘門擋下走 fallback（witness 用）。
  var rejectedWhileOpen: bool

  // 稽核用：是否確實發生過「視窗已過期時讀取計數」，讓 :287-293 的歸零真的 materialize。
  var expiredWindowRead: bool

  // ---------------------------------------------------------------------------
  // hasFailureWindowElapsed(windowStart, now)（CacheErrorHandler.java:153-155）
  //
  // `Duration.between(windowStart, now).compareTo(failureWindow) >= 0`——#73 把
  // 原本的嚴格大於改成大於或等於（恰好相隔一個視窗的兩次失敗不再併入同一視窗）。
  // windowStart < 0 對應 firstFailureAt == null：還沒有視窗，不算過期。
  // ---------------------------------------------------------------------------

  pure def failureWindowElapsedAt(windowStart: int, clock: int, window: int): bool =
    windowStart >= 0 and clock - windowStart >= window

  // getConsecutiveFailureCount()（:275-278）＋ expireElapsedFailureWindow()（:287-293）：
  // 讀取時視窗已過期就是 0。registerClosedStateFailure（:140）用的也是同一個判斷。
  pure def observedFailureCount(memo: int, windowStart: int, clock: int, window: int): int =
    if (failureWindowElapsedAt(windowStart, clock, window)) 0 else memo

  // 當前狀態下視窗是否已過期。
  val failureWindowElapsed: bool = failureWindowElapsedAt(windowStartedAt, now, failureWindow)

  // ---------------------------------------------------------------------------
  // shouldBypassOperation()（CacheErrorHandler.java:180-197）
  // ---------------------------------------------------------------------------

  // `if (!circuitOpen) return false;`（:181-183）——Closed 一律放行。
  val gateClosedAdmits: bool = not(circuitOpen)

  // `openedAt != null && Duration.between(openedAt, now) > circuitOpenDuration`（:186-187）
  // ——recovery timer 已到期（此處仍是嚴格大於，#73 只改失敗計數視窗）；
  // 等價於 invariants.qnt 的 circuitState == HalfOpen。
  val gateTimerExpired: bool =
    circuitOpen and circuitOpenedAt >= 0 and now - circuitOpenedAt > circuitOpenDuration

  // `halfOpenTrialActive.compareAndSet(false, true)`（:188）——只有搶到的那一個放行。
  val gateTrialAdmits: bool = gateTimerExpired and not(halfOpenTrialActive)

  // 閘門放行與否；其餘情況 `return true`（:193、:196）＝ bypass。
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
    // 只有 Closed → Open 轉移會改寫（見 failWhileClosed）。
    failuresAtLastOpening' = failuresAtLastOpening,
  }

  // 失敗計數的唯一寫入口：欄位記憶值、視窗起點，以及由兩者＋時鐘推得的**可見計數**
  // 一起賦值，保證模型裡的 consecutiveFailures 永遠等於讀取者會拿到的值。
  action setFailureWindow(memo: int, windowStart: int, clock: int): bool = all {
    memoFailureCount' = memo,
    windowStartedAt' = windowStart,
    consecutiveFailures' = observedFailureCount(memo, windowStart, clock, failureWindow),
  }

  // 不動失敗計數的步驟（時鐘也沒變）。
  action keepFailureWindow: bool = setFailureWindow(memoFailureCount, windowStartedAt, now)

  // `consecutiveFailures.set(0); firstFailureAt = null;`（recordSuccess :227-228、
  // closeCircuit :269-270、resetErrorState :249-250）。
  action clearFailureWindow: bool = setFailureWindow(0, neverOpened, now)

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
    expiredWindowRead' = expiredWindowRead,
  }

  action keepThreads: bool = threads' = threads

  // openCircuit()（:259-265）：開路、重新起算 time-out、釋放試探名額、累計開路次數。
  // **不動** consecutiveFailures／firstFailureAt（程式同樣沒有動）。
  // 同時讓「本次 Open 情境」的輔助計量歸零。
  action doOpenCircuit: bool = all {
    circuitOpen' = true,
    circuitOpenedAt' = now,
    halfOpenTrialActive' = false,
    totalCircuitOpenings' = totalCircuitOpenings + 1,
    halfOpenAdmitted' = 0,
    halfOpenSuccesses' = 0,
    // 這個組合積木只服務 failWhileOpenPath（:114-120）：電路**本來就開著**，
    // 不是 Closed → Open 轉移，因此不更新 failuresAtLastOpening（invariants.qnt:48-51）。
    failuresAtLastOpening' = failuresAtLastOpening,
  }

  // ---------------------------------------------------------------------------
  // init
  // ---------------------------------------------------------------------------

  action init: bool = all {
    circuitOpen' = false,
    circuitOpenedAt' = neverOpened,
    now' = 0,
    // consecutiveFailures == 0（:25）、firstFailureAt == null（:26）。
    setFailureWindow(0, neverOpened, 0),
    // 尚未發生任何 Closed → Open 轉移。
    failuresAtLastOpening' = 0,
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
    expiredWindowRead' = false,
  }

  // ---------------------------------------------------------------------------
  // 時間推進（LocalDateTime.now(clock)；#73 起時鐘可注入，:23）
  // ---------------------------------------------------------------------------

  // 這一刻之後 recovery timer 是否已到期（Open 期滿 → Half-Open 情境）。
  val timerExpiresAfterTick: bool =
    circuitOpen and circuitOpenedAt >= 0 and (now + 1) - circuitOpenedAt > circuitOpenDuration

  action tick: bool = all {
    now' = now + 1,
    // 時間推進本身就可能讓失敗計數視窗過期——欄位記憶值不動，但下一刻任何讀取
    // 都會拿到 0（:275-293）。
    setFailureWindow(memoFailureCount, windowStartedAt, now + 1),
    // Open 期滿：上一次 Half-Open 失敗所要求的「回到 Open」已履行完畢。
    halfOpenFailed' = if (timerExpiresAfterTick) false else halfOpenFailed,
    halfOpenSuccesses' = halfOpenSuccesses,
    halfOpenAdmitted' = halfOpenAdmitted,
    lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
    keepBreaker,
    keepErrorStats,
    keepAudit,
    keepThreads,
  }

  // ---------------------------------------------------------------------------
  // executeWithFallback／executeVoidOperation（:63-103）
  // ---------------------------------------------------------------------------

  // 閘門放行：請求進入受保護操作。circuitOpen 為真時走的是 half-open 試探路徑。
  action beginRequest(t: int, op: str): bool = {
    val trial = circuitOpen
    all {
      threads.get(t).pc == Idle,
      REQUEST_OPERATIONS.contains(op),
      gateAdmits,
      threads' = threads.put(t, { pc: Running, op: op, trial: trial }),
      // compareAndSet(false, true) 成功（:188）。
      halfOpenTrialActive' = (trial or halfOpenTrialActive),
      // 放行「當下」的狀態決定計量歸屬（Issue #50）。
      halfOpenAdmitted' = if (circuitState == HalfOpen) halfOpenAdmitted + 1 else halfOpenAdmitted,
      admittedWhileOpen' = if (circuitState == Open) admittedWhileOpen + 1 else admittedWhileOpen,
      rejectedWhileOpen' = rejectedWhileOpen,
      expiredWindowRead' = expiredWindowRead,
      circuitOpen' = circuitOpen,
      circuitOpenedAt' = circuitOpenedAt,
      totalCircuitOpenings' = totalCircuitOpenings,
      failuresAtLastOpening' = failuresAtLastOpening,
      halfOpenSuccesses' = halfOpenSuccesses,
      halfOpenFailed' = halfOpenFailed,
      lastHalfOpenFailureAt' = lastHalfOpenFailureAt,
      keepClock,
      keepFailureWindow,
      keepErrorStats,
    }
  }

  // 閘門擋下（:68-73、:87-92）：recordError("Circuit breaker open")＋建議 fallback，
  // 不執行受保護操作，呼叫立刻返回（呼叫端回到 Idle）。
  action rejectRequest(t: int, op: str): bool = all {
    threads.get(t).pc == Idle,
    REQUEST_OPERATIONS.contains(op),
    not(gateAdmits),
    errorCounts' = errorCounts.put(op, errorCounts.get(op) + 1),
    lastErrorTimes' = lastErrorTimes.put(op, now),
    fallbackRecommendations' = fallbackRecommendations + 1,
    rejectedWhileOpen' = (rejectedWhileOpen or circuitState == Open),
    admittedWhileOpen' = admittedWhileOpen,
    expiredWindowRead' = expiredWindowRead,
    keepClock,
    keepBreaker,
    keepFailureWindow,
    keepHalfOpenAux,
    keepThreads,
  }

  // ---------------------------------------------------------------------------
  // recordSuccess(operationName)（:226-235）
  // ---------------------------------------------------------------------------

  action finishSuccess(t: int): bool = {
    val th = threads.get(t)
    // `if (circuitOpen) { closeCircuit(); }`（:231-234）。
    val closes = circuitOpen
    all {
      th.pc == Running,
      // `consecutiveFailures.set(0); firstFailureAt = null;`（:227-228）。
      clearFailureWindow,
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
      // 關路不是 Closed → Open 轉移，歷史紀錄保留（見檔頭與未決事項 3）。
      failuresAtLastOpening' = failuresAtLastOpening,
      fallbackRecommendations' = fallbackRecommendations,
      threads' = threads.put(t, IDLE_THREAD),
      keepClock,
      keepAudit,
    }
  }

  // ---------------------------------------------------------------------------
  // handleCacheError(exception, operationName, key)（:105-126）
  // ---------------------------------------------------------------------------

  // `if (circuitOpen) { openCircuit(); return; }`（:114-120，#56 的修復）：
  // 失敗發生時電路仍在 Open／Half-Open 路徑上 → 立刻重新開路並重新起算 time-out，
  // 不動 Closed 的失敗計數與視窗起點。
  action failWhileOpenPath(t: int): bool = {
    val th = threads.get(t)
    all {
      th.pc == Running,
      circuitOpen,
      errorCounts' = errorCounts.put(th.op, errorCounts.get(th.op) + 1),
      lastErrorTimes' = lastErrorTimes.put(th.op, now),
      fallbackRecommendations' = fallbackRecommendations + 1,
      doOpenCircuit,
      halfOpenFailed' = (th.trial or halfOpenFailed),
      lastHalfOpenFailureAt' = if (th.trial) now else lastHalfOpenFailureAt,
      keepFailureWindow,
      threads' = threads.put(t, IDLE_THREAD),
      keepClock,
      keepAudit,
    }
  }

  // `int failures = registerClosedStateFailure(); if (failures >= failureThreshold)`
  // （:122-125 ＋ :137-146）：失敗發生時電路是 Closed。視窗以 firstFailureAt 為錨點，
  // `windowStart == null || hasFailureWindowElapsed(windowStart, now)` 成立時整段重設
  // 為「這一次失敗開啟的新視窗」（計數 1、錨點 now）。#73 起邊界含等於。
  action failWhileClosed(t: int): bool = {
    val th = threads.get(t)
    val windowExpired = windowStartedAt < 0 or now - windowStartedAt >= failureWindow
    // `consecutiveFailures.set(1); return 1;`（:142-143）／`incrementAndGet()`（:145）。
    val failures = if (windowExpired) 1 else memoFailureCount + 1
    val opens = failures >= failureThreshold
    all {
      th.pc == Running,
      not(circuitOpen),
      errorCounts' = errorCounts.put(th.op, errorCounts.get(th.op) + 1),
      lastErrorTimes' = lastErrorTimes.put(th.op, now),
      fallbackRecommendations' = fallbackRecommendations + 1,
      setFailureWindow(failures, if (windowExpired) now else windowStartedAt, now),
      circuitOpen' = opens,
      circuitOpenedAt' = if (opens) now else circuitOpenedAt,
      halfOpenTrialActive' = if (opens) false else halfOpenTrialActive,
      totalCircuitOpenings' = if (opens) totalCircuitOpenings + 1 else totalCircuitOpenings,
      // 唯一的 Closed → Open 轉移（:123-125）：記錄轉移當下 registerClosedStateFailure()
      // 回傳的失敗數，也就是與 failureThreshold 比較的那個值。
      failuresAtLastOpening' = if (opens) failures else failuresAtLastOpening,
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
  // getConsecutiveFailureCount()（:275-278）→ expireElapsedFailureWindow()（:287-293）
  //
  // #73 新增的讀取路徑：CacheHealthIndicator.java:180 與 OrdersInfoContributor.java:34
  // 都走這裡。視窗已過期時把欄位與錨點一起歸零（materialize），否則什麼都不動。
  // 對可見計數 consecutiveFailures 沒有影響——它本來就已經是過期即 0 的值。
  // ---------------------------------------------------------------------------

  action readFailureCount: bool = all {
    setFailureWindow(
      if (failureWindowElapsed) 0 else memoFailureCount,
      if (failureWindowElapsed) neverOpened else windowStartedAt,
      now,
    ),
    expiredWindowRead' = (expiredWindowRead or failureWindowElapsed),
    admittedWhileOpen' = admittedWhileOpen,
    rejectedWhileOpen' = rejectedWhileOpen,
    keepClock,
    keepBreaker,
    keepHalfOpenAux,
    keepErrorStats,
    keepThreads,
  }

  // ---------------------------------------------------------------------------
  // checkCacheHealth(healthCheck)（:199-214）
  // ---------------------------------------------------------------------------

  // healthCheck 回 true → closeCircuit()（:201-204）；程式不檢查當下狀態，
  // 即使電路本來就是 Closed 也會把計數與計時器清乾淨。
  action healthCheckPass: bool = all {
    circuitOpen' = false,
    circuitOpenedAt' = neverOpened,
    halfOpenTrialActive' = false,
    clearFailureWindow,
    halfOpenAdmitted' = 0,
    halfOpenFailed' = false,
    lastHalfOpenFailureAt' = neverOpened,
    halfOpenSuccesses' = halfOpenSuccesses,
    totalCircuitOpenings' = totalCircuitOpenings,
    failuresAtLastOpening' = failuresAtLastOpening,
    keepClock,
    keepErrorStats,
    keepAudit,
    keepThreads,
  }

  // healthCheck 丟例外 → 只 recordError("health-check")（:209-213）；電路狀態不變。
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
  // resetErrorState()（:248-257）；totalCircuitOpenings 不在重設範圍內。
  // ---------------------------------------------------------------------------

  action resetState: bool = all {
    clearFailureWindow,
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
    failuresAtLastOpening' = failuresAtLastOpening,
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
      readFailureCount,
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

  // INV_openRequiresThresholdReached（轉移性質的記錄側）：Closed → Open 的轉移確實發生過
  // 並被記錄下來——電路目前是 Open，且 failuresAtLastOpening 已由某次 failWhileClosed
  // 寫入（init 為 0，只有轉移會寫）。
  val WIT_closedToOpenTransitionRecorded: bool =
    circuitState == Open and failuresAtLastOpening > 0

  // INV_openRequiresThresholdReached（門檻豁免路徑）：本不變量刻意不涵蓋「Half-Open 試探
  // 失敗立刻重新開路」（source.md：enters the Open state immediately）。這條 witness 確認
  // 該路徑在抽樣中確實走到過——目前這段 Open 就是由試探失敗當下重新起算的
  // （circuitOpenedAt == lastHalfOpenFailureAt，CacheErrorHandler.java:114-120 → :261），
  // 因此不變量的「成立」不是因為這個分支從未執行。
  val WIT_trialFailureReopenedCircuit: bool =
    circuitState == Open and lastHalfOpenFailureAt >= 0 and circuitOpenedAt == lastHalfOpenFailureAt

  // INV_closedFailureCounterResetsPeriodically：Closed 期間有過失敗，而且自該視窗
  // 起點起算已經整整經過一個計數視窗（時間確實推進到「該自動歸零」的時點）。
  val WIT_failureWindowFullyElapsed: bool =
    circuitState == Closed and windowStartedAt >= 0 and now - windowStartedAt >= failureWindow

  // INV_closedFailureCounterResetsPeriodically（#73 的語意）：欄位記憶值還留著舊的
  // 非零計數，而視窗已經走完——此時讀取者拿到的計數是 0。描述的是「過期即 0」
  // 這個修復行為確實被觸及的情境。
  val WIT_staleMemoReadsAsZero: bool =
    memoFailureCount > 0 and failureWindowElapsed and consecutiveFailures == 0

  // INV_closedFailureCounterResetsPeriodically（#73 的讀取路徑）：確實有讀取者在視窗
  // 過期後呼叫 getConsecutiveFailureCount()，讓 :287-293 的歸零真的寫回欄位。
  val WIT_expiredWindowMaterializedByRead: bool = expiredWindowRead

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
