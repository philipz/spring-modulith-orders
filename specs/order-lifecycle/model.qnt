module model {
  import invariants.* from "./invariants"
  export invariants.*

  // 訂單生命週期 as-is 模型（agent-write-spec 模型階段，ADR-018）。
  //
  // 來源：specs/order-lifecycle/source.md 的 R1–R6 為「規格」；
  //       本檔描述「程式現況」，程式碼為：
  //       src/main/java/com/sivalabs/bookstore/orders/domain/OrderService.java
  //       src/main/java/com/sivalabs/bookstore/orders/domain/OrderEntity.java
  //       src/main/java/com/sivalabs/bookstore/orders/domain/OrderRepository.java
  //
  // 不變量：invariants.qnt（已核准，不得修改）。以上 import／export 讓
  // instances.qnt 的實例能看見 INV_*；缺少 export 會導致 QNT404。

  // ---- 模型層常數 ----

  // 可建立的訂單編號集合（符號化；程式以 UUID 產生編號，未限制數量）。
  const ORDER_IDS: Set[str]

  pure val allStatuses: Set[OrderStatus] =
    Set(NEW, PENDING, CONFIRMED, IN_PROCESS, SHIPPED, DELIVERED, CANCELLED, ERROR)

  // ---- 模型層型別 ----

  // 一個「已讀取、尚未提交」的狀態變更交易（begin 已執行，commit 未執行）。
  // readStatus 為 begin 當下讀到的已提交狀態；writeStatus 為交易打算寫入的狀態。
  // 對應 OrderService.updateOrderStatus 與 cancelOrder 的 read-modify-write 兩段。
  type Txn = {
    order: str,
    readStatus: OrderStatus,
    writeStatus: OrderStatus,
  }

  // ---- 模型層狀態 ----
  //
  // orders（來自 invariants.qnt）為「已提交」的狀態序列；pending 為進行中的交易。
  // OrderEntity 無 @Version、無 @Lock，OrderRepository 亦無鎖定查詢
  // （OrderEntity.java 全檔、OrderRepository.findByOrderNumber），
  // 因此交易之間允許交錯，且可能以過期讀取覆寫已提交狀態。
  var pending: Set[Txn]

  // ---- 輔助函式 ----

  // 已提交序列的最後一筆寫入（序列至少一筆；init 不建立空序列的訂單）。
  pure def lastWrite(ws: List[StatusWrite]): StatusWrite =
    ws.nth(ws.length() - 1)

  // 訂單目前的已提交狀態。
  def currentStatus(k: str): OrderStatus =
    lastWrite(writesOf(k)).writtenStatus

  // ---- State machine ----

  // 初始狀態：沒有任何訂單，也沒有進行中的交易。
  // 不變量在初始狀態全為空真；witness 亦不成立（見 WIT_*）。
  action init: bool = all {
    orders' = Map(),
    pending' = Set(),
  }

  // createOrder（OrderService.java:30-55）：
  //   - 只有當 status 為 null 才設為 NEW（:39-41）；呼叫端傳入的既有 status 不會被檢查。
  //   - save 立即提交此筆建立寫入。
  // 因此建立時的 writtenStatus 可為任意 OrderStatus（s 由 step 非決定選擇）。
  action createOrder(k: str, s: OrderStatus): bool = all {
    not(orders.keys().contains(k)),
    orders' = orders.put(k, { writes: List({ readStatus: NEW, writtenStatus: s }) }),
    pending' = pending,
  }

  // updateOrderStatus 的第一段（OrderService.java:97-108）：
  //   讀取現況（:98-100）後「無任何轉移檢查」地寫入 newStatus（:102-104）。
  //   提交（第二段）前狀態只存在於交易內，故以 pending 表示。
  action beginUpdate(k: str, s: OrderStatus): bool = all {
    orders.keys().contains(k),
    pending' = pending.union(Set({
      order: k,
      readStatus: currentStatus(k),
      writeStatus: s,
    })),
    orders' = orders,
  }

  // cancelOrder 的第一段（OrderService.java:116-129）：
  //   讀取現況後檢查 canBeCancelled（:121-124），不在 NEW／PENDING 則拋例外、
  //   交易不提交（模型不建立 pending）。通過後打算寫入 CANCELLED（:126-127）。
  action beginCancel(k: str): bool = all {
    orders.keys().contains(k),
    canCancelFrom(currentStatus(k)),
    pending' = pending.union(Set({
      order: k,
      readStatus: currentStatus(k),
      writeStatus: CANCELLED,
    })),
    orders' = orders,
  }

  // 交易提交：把 (readStatus, writeStatus) 附加到已提交序列。
  // JPA 的 UPDATE 不帶版本條件，會直接覆寫列；以過期 readStatus 提交即為覆寫。
  action commit(txn: Txn): bool = all {
    pending.contains(txn),
    orders.keys().contains(txn.order),
    orders' = orders.put(txn.order, {
      writes: writesOf(txn.order).append({
        readStatus: txn.readStatus,
        writtenStatus: txn.writeStatus,
      }),
    }),
    pending' = pending.exclude(Set(txn)),
  }

  // ---- 非決定選擇 ----

  action createAction: bool = {
    nondet k = ORDER_IDS.oneOf()
    nondet s = allStatuses.oneOf()
    createOrder(k, s)
  }

  action updateAction: bool = {
    nondet k = ORDER_IDS.oneOf()
    nondet s = allStatuses.oneOf()
    beginUpdate(k, s)
  }

  action cancelAction: bool = {
    nondet k = ORDER_IDS.oneOf()
    beginCancel(k)
  }

  action commitAction: bool = {
    nondet txn = pending.oneOf()
    commit(txn)
  }

  action step: bool = any {
    createAction,
    updateAction,
    cancelAction,
    commitAction,
  }

  // ---- 情境 witness（每條 INV_* 至少一個）----
  //
  // 全部以正面敘述書寫、描述「不變量要保護的情境確實發生」，
  // 且初始狀態（orders 為空）不成立。

  // INV_newOrderStartsNew：有訂單以 NEW 建立（第一筆已提交寫入為 NEW）。
  val WIT_orderCreatedAsNew: bool =
    orders.keys().exists(k => writesOf(k).nth(0).writtenStatus == NEW)

  // INV_normalFlowIsSingleStep：有相鄰兩筆正常狀態且階數恰好 +1。
  val WIT_normalForwardStep: bool =
    orders.keys().exists(k =>
      adjacentIndices(k).exists(i =>
        isNormalStatus(writesOf(k).nth(i).writtenStatus)
          and isNormalStatus(writesOf(k).nth(i + 1).writtenStatus)
          and normalRank(writesOf(k).nth(i + 1).writtenStatus)
            == normalRank(writesOf(k).nth(i).writtenStatus) + 1))

  // INV_cancelOnlyFromNewOrPending：有一筆取消是從 NEW／PENDING 提交。
  val WIT_cancelFromAllowed: bool =
    orders.keys().exists(k =>
      adjacentIndices(k).exists(i =>
        writesOf(k).nth(i + 1).writtenStatus == CANCELLED
          and canCancelFrom(writesOf(k).nth(i).writtenStatus)))

  // INV_errorOnlyFromAllowed：有一筆 ERROR 是從允許的來源狀態提交。
  val WIT_errorFromAllowed: bool =
    orders.keys().exists(k =>
      adjacentIndices(k).exists(i =>
        writesOf(k).nth(i + 1).writtenStatus == ERROR
          and canErrorFrom(writesOf(k).nth(i).writtenStatus)))

  // INV_onlyPermittedTransitions：有一筆相鄰寫入是 R2–R4 允許的轉移。
  val WIT_permittedTransition: bool =
    orders.keys().exists(k =>
      adjacentIndices(k).exists(i =>
        isAllowedTransition(
          writesOf(k).nth(i).writtenStatus,
          writesOf(k).nth(i + 1).writtenStatus)))

  // INV_committedWritesAreSequentialAndFresh：有相鄰寫入是「合法且讀到前一筆」。
  val WIT_freshSequentialWrite: bool =
    orders.keys().exists(k =>
      adjacentIndices(k).exists(i =>
        sequentialStep(writesOf(k).nth(i), writesOf(k).nth(i + 1))))
}
