// Circuit Breaker as-is 模型的具體實例（ADR-018 模型階段、Q21）。
//
// 每個模組把 model.qnt 的常數固定成一組具體設定。設定範圍以**程式實際接受的輸入**
// 為準（每個常數的出處見 verify.yml 的 domain_justification）：
//   - failureThreshold、circuitOpenDuration、failureWindow 由 @Value 注入
//     （CacheErrorHandler.java:34-41），程式沒有任何範圍檢查 → 涵蓋邊界值與奇偶。
//   - THREADS 是併發呼叫端，程式未限制數量 → 涵蓋 2 與 3。
//   - successThreshold、maxHalfOpenRequests 程式無對應設定 → 依 Issue #50 採規格
//     最小合法值 1。

// 邊界組：門檻 1（首次失敗即開路）、time-out 1、視窗 2（偶數）、2 個呼叫端。
module cb_t1_d1_w2 {
  import model(
    failureThreshold = 1,
    successThreshold = 1,
    circuitOpenDuration = 1,
    failureWindow = 2,
    maxHalfOpenRequests = 1,
    THREADS = Set(1, 2)
  ).* from "./model"
}

// 偶數組：門檻 2、time-out 2、視窗 3（奇數）、2 個呼叫端。
module cb_t2_d2_w3 {
  import model(
    failureThreshold = 2,
    successThreshold = 1,
    circuitOpenDuration = 2,
    failureWindow = 3,
    maxHalfOpenRequests = 1,
    THREADS = Set(1, 2)
  ).* from "./model"
}

// 奇數組：門檻 3、time-out 1（邊界）、視窗 2、3 個呼叫端（更多交錯）。
module cb_t3_d1_w2_c3 {
  import model(
    failureThreshold = 3,
    successThreshold = 1,
    circuitOpenDuration = 1,
    failureWindow = 2,
    maxHalfOpenRequests = 1,
    THREADS = Set(1, 2, 3)
  ).* from "./model"
}

// 單一呼叫端組（邊界：完全沒有併發）：門檻 2、time-out 3（奇數）、視窗 4（偶數）。
// 用來區分「只有交錯才會出現」與「連單執行緒都會出現」的候選發現。
module cb_t2_d3_w4_c1 {
  import model(
    failureThreshold = 2,
    successThreshold = 1,
    circuitOpenDuration = 3,
    failureWindow = 4,
    maxHalfOpenRequests = 1,
    THREADS = Set(1)
  ).* from "./model"
}
