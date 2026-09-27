// 訂單生命週期模型的具體實例（agent-write-spec 模型階段，ADR-018）。
//
// 每個 module 對應 verify.yml 的一個 instance，常數與 verify.yml 一致。
//
// ORDER_IDS 為符號化的訂單編號集合。程式對「同時存在的訂單筆數」沒有任何檢查：
//   - OrderService.java:36-38：orderNumber 為空時以 UUID.randomUUID() 產生
//   - OrderMapper.java:17：建立 entity 時一律指派新的 UUID
//   - OrderRepository.java：只有查詢與 updateTimestamps，沒有數量上限或檢查
// 依建模規則 1（程式未限制 → 涵蓋邊界值與奇偶兩種情況），取 1（最小邊界）、
// 2（偶數）、3（奇數）。
//
// 並行交錯的強度來自「同一訂單上同時存在的未提交交易數」，那由 step 的非決定選擇
// 產生、不受 ORDER_IDS 大小限制；多一個訂單編號只是多一組彼此獨立的鍵。

module oneOrder {
  import model(ORDER_IDS = Set("o1")).* from "./model"
}

module twoOrders {
  import model(ORDER_IDS = Set("o1", "o2")).* from "./model"
}

module threeOrders {
  import model(ORDER_IDS = Set("o1", "o2", "o3")).* from "./model"
}
