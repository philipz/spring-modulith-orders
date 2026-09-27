// Circuit Breaker as-is 模型的具體實例（ADR-018 模型階段、Q21）。
//
// 每個模組把 model.qnt 的常數固定成一組具體設定。設定範圍以程式實際接受的
// 輸入為準（見 verify.yml 各常數的 domain_justification）：failureThreshold 與
// circuitOpenDuration 由 @Value 注入、程式未限制，故涵蓋邊界值與奇偶；
// successThreshold／maxHalfOpenRequests／failureWindow 程式無對應設定，依
// Issue #50 採規格最小合法值與固定視窗。

// failureThreshold 邊界 1（首次失敗即開路）；duration 邊界 1；window 2。
module cb_t1_d1_w2 {
  import model(
    failureThreshold = 1,
    successThreshold = 1,
    circuitOpenDuration = 1,
    failureWindow = 2,
    maxHalfOpenRequests = 1
  ).* from "./model"
}

// failureThreshold 偶數 2；duration 偶數 2；window 奇數 3。
module cb_t2_d2_w3 {
  import model(
    failureThreshold = 2,
    successThreshold = 1,
    circuitOpenDuration = 2,
    failureWindow = 3,
    maxHalfOpenRequests = 1
  ).* from "./model"
}

// failureThreshold 奇數 3；duration 邊界 1；window 2。
module cb_t3_d1_w2 {
  import model(
    failureThreshold = 3,
    successThreshold = 1,
    circuitOpenDuration = 1,
    failureWindow = 2,
    maxHalfOpenRequests = 1
  ).* from "./model"
}
