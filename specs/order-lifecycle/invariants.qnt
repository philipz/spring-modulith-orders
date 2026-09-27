// 訂單生命週期不變量（agent-write-spec 不變量階段，ADR-018）。
//
// 來源：specs/order-lifecycle/source.md（CI 寫入的快照，不得修改任何字元）。
// 本檔只描述規格（source.md 的 R1–R6）要求「必須永遠成立」的性質，不描述程式現況。
// 程式碼僅用來取得狀態詞彙：OrderStatus 的成員名稱取自
// src/main/java/com/sivalabs/bookstore/orders/api/model/OrderStatus.java。
//
// 供模型階段使用的狀態介面：
//   - `orders`：每筆訂單的觀測狀態，鍵為訂單編號（程式為 String orderNumber）。
//   - `Order.writes`：該訂單「已提交的狀態寫入」序列，由舊到新；索引 0 為建立時的寫入。
//     每筆 StatusWrite 記錄該次交易「讀到的狀態」（readStatus）與「寫入的狀態」
//     （writtenStatus）。這是檢查 R6（不得依過期讀取覆寫）所需的規格層觀測量，
//     並非程式欄位；目前狀態即最後一筆 writtenStatus。
//
// 本檔不得定義任何 witness：witness 屬模型階段（model.qnt）。

module invariants {
  type OrderStatus =
    | NEW
    | PENDING
    | CONFIRMED
    | IN_PROCESS
    | SHIPPED
    | DELIVERED
    | CANCELLED
    | ERROR

  // 一次已提交的狀態寫入：交易讀到的狀態，以及它寫入的狀態。
  type StatusWrite = {
    readStatus: OrderStatus,
    writtenStatus: OrderStatus,
  }

  type Order = {
    // 已提交的狀態寫入序列，由舊到新；writes[0] 為建立時的寫入。
    writes: List[StatusWrite],
  }

  // ---- R2–R5 的轉移謂詞（技術性輔助，非不變量）----

  pure def isNormalStatus(s: OrderStatus): bool =
    s == NEW or s == PENDING or s == CONFIRMED
      or s == IN_PROCESS or s == SHIPPED or s == DELIVERED

  pure def normalRank(s: OrderStatus): int =
    if (s == NEW) 0
    else if (s == PENDING) 1
    else if (s == CONFIRMED) 2
    else if (s == IN_PROCESS) 3
    else if (s == SHIPPED) 4
    else if (s == DELIVERED) 5
    else -1

  pure def canCancelFrom(s: OrderStatus): bool =
    s == NEW or s == PENDING

  pure def canErrorFrom(s: OrderStatus): bool =
    s == NEW or s == PENDING or s == CONFIRMED or s == IN_PROCESS

  // R2–R5 允許的 (前一狀態, 下一狀態) 配對；終態不在任何允許配對的來源端，
  // 因此「終態不得再轉移」與「R2–R4 以外的轉移一律不允許」同時被涵蓋。
  pure def isAllowedTransition(prev: OrderStatus, nxt: OrderStatus): bool =
    (isNormalStatus(prev) and isNormalStatus(nxt)
      and normalRank(nxt) == normalRank(prev) + 1)
    or (nxt == CANCELLED and canCancelFrom(prev))
    or (nxt == ERROR and canErrorFrom(prev))

  pure def normalFlowStep(prev: StatusWrite, nxt: StatusWrite): bool =
    (isNormalStatus(prev.writtenStatus) and isNormalStatus(nxt.writtenStatus))
      implies normalRank(nxt.writtenStatus) == normalRank(prev.writtenStatus) + 1

  pure def cancelStep(prev: StatusWrite, nxt: StatusWrite): bool =
    (nxt.writtenStatus == CANCELLED) implies canCancelFrom(prev.writtenStatus)

  pure def errorStep(prev: StatusWrite, nxt: StatusWrite): bool =
    (nxt.writtenStatus == ERROR) implies canErrorFrom(prev.writtenStatus)

  pure def permittedStep(prev: StatusWrite, nxt: StatusWrite): bool =
    isAllowedTransition(prev.writtenStatus, nxt.writtenStatus)

  pure def freshReadStep(prev: StatusWrite, nxt: StatusWrite): bool =
    nxt.readStatus == prev.writtenStatus

  // R6：(a) 已提交的序列必須是合法的逐一執行（permittedStep），且
  // (b) 每次寫入都讀到緊接的前一筆已提交狀態（freshReadStep，不得用過期讀取覆寫）。
  pure def sequentialStep(prev: StatusWrite, nxt: StatusWrite): bool =
    permittedStep(prev, nxt) and freshReadStep(prev, nxt)

  var orders: str -> Order

  def writesOf(k: str): List[StatusWrite] =
    orders.get(k).writes

  // 具有「前一筆」的索引集合（0 沒有前一筆）。空序列或單筆序列時為空集合，
  // 因此不會對序列外的索引取值。
  def adjacentIndices(k: str): Set[int] = {
    val ws = writesOf(k)
    ws.indices().filter(i => i + 1 < ws.length())
  }

  // source: source.md §R1
  // 「R1 狀態集合：NEW、PENDING、CONFIRMED、IN_PROCESS、SHIPPED、DELIVERED、CANCELLED、ERROR。新建立的訂單狀態為 NEW。」
  val INV_newOrderStartsNew: bool =
    orders.keys().forall(k => writesOf(k).nth(0).writtenStatus == NEW)

  // source: source.md §R2
  // 「R2 正常流程單向前進，不可跳階、不可倒退：NEW → PENDING → CONFIRMED → IN_PROCESS → SHIPPED → DELIVERED。」
  val INV_normalFlowIsSingleStep: bool =
    orders.keys().forall(k =>
      adjacentIndices(k).forall(i =>
        normalFlowStep(writesOf(k).nth(i), writesOf(k).nth(i + 1))))

  // source: source.md §R3
  // 「R3 取消：只有 NEW、PENDING 的訂單可以轉為 CANCELLED。」
  val INV_cancelOnlyFromNewOrPending: bool =
    orders.keys().forall(k =>
      adjacentIndices(k).forall(i =>
        cancelStep(writesOf(k).nth(i), writesOf(k).nth(i + 1))))

  // source: source.md §R4
  // 「R4 錯誤：NEW、PENDING、CONFIRMED、IN_PROCESS 的訂單可以轉為 ERROR。」
  val INV_errorOnlyFromAllowed: bool =
    orders.keys().forall(k =>
      adjacentIndices(k).forall(i =>
        errorStep(writesOf(k).nth(i), writesOf(k).nth(i + 1))))

  // source: source.md §R5
  // 「R5 終態：DELIVERED、CANCELLED、ERROR 為終態，進入後不得再轉移。R2–R4 以外的轉移一律不允許。」
  val INV_onlyPermittedTransitions: bool =
    orders.keys().forall(k =>
      adjacentIndices(k).forall(i =>
        permittedStep(writesOf(k).nth(i), writesOf(k).nth(i + 1))))

  // source: source.md §R6
  // 「R6 並行：同一訂單同時有多個狀態變更時，結果必須等同於這些變更依某個順序逐一執行的結果；不得依過期的讀取覆寫狀態（例如已出貨的訂單被取消）。」
  val INV_committedWritesAreSequentialAndFresh: bool =
    orders.keys().forall(k =>
      adjacentIndices(k).forall(i =>
        sequentialStep(writesOf(k).nth(i), writesOf(k).nth(i + 1))))
}
