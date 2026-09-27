// 訂單生命週期模型的具體實例（agent-write-spec 模型階段，ADR-018）。
//
// 每個 module 對應 verify.yml 的一個 instance，常數與 verify.yml 一致。
// ORDER_IDS 為符號化的訂單編號集合：
//   - 程式以 UUID 產生訂單編號（OrderService.java:35-37、OrderMapper.java:16），
//     訂單數量未限制，故此處涵蓋邊界 1 與奇／偶 2、3。
//   - 真正的並行交錯來自同一訂單上的多個進行中交易（pending），
//     與訂單張數無關；多一張訂單只是多一組獨立鍵可交錯。

module oneOrder {
  import model(ORDER_IDS = Set("o1")).* from "./model"
}

module twoOrders {
  import model(ORDER_IDS = Set("o1", "o2")).* from "./model"
}

module threeOrders {
  import model(ORDER_IDS = Set("o1", "o2", "o3")).* from "./model"
}
