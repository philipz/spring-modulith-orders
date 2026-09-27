module model {
  import invariants.* from "./invariants"
  export invariants.*

  // 訂單生命週期 as-is 模型（agent-write-spec 模型階段，ADR-018）。
  //
  // 來源：specs/order-lifecycle/source.md 的 R1–R6 為「規格」（已核准，不得修改）；
  //       本檔描述「程式現況」，逐一對應下列檔案（行號為本次建模時的 trunk）：
  //       src/main/java/com/sivalabs/bookstore/orders/domain/OrderService.java
  //       src/main/java/com/sivalabs/bookstore/orders/domain/OrderEntity.java
  //       src/main/java/com/sivalabs/bookstore/orders/domain/OrderRepository.java
  //
  // 2026-09-27 重跑（修復後複驗）：程式已依 #57 在 createOrder／updateOrderStatus 加上
  // 狀態轉移檢查與初始狀態限制（OrderService.java:40-44、:105-109、:148-166），並依 #58
  // 在 OrderEntity 加上 @Version 樂觀鎖欄位（OrderEntity.java:85-87）。本檔依「目前」的
  // 程式重建模型，不是修復前的模型。
  //
  // 不變量：invariants.qnt（已核准，不得修改）。以上 import／export 讓 instances.qnt 的
  // 實例能看見 INV_*；缺少 export 會導致 QNT404。

  // ---- 模型層常數 ----

  // 可建立的訂單編號集合（符號化；程式以 UUID 產生編號，未限制訂單筆數）。
  const ORDER_IDS: Set[str]

  // R1 的狀態集合，取自 api/model/OrderStatus.java（8 個列舉成員）。
  pure val allStatuses: Set[OrderStatus] =
    Set(NEW, PENDING, CONFIRMED, IN_PROCESS, SHIPPED, DELIVERED, CANCELLED, ERROR)

  // ---- 模型層型別 ----

  // 一個「已讀取、尚未提交」的狀態變更交易（begin 已執行、commit 未執行）。
  //   - readStatus ：begin 當下由 findByOrderNumber 讀到的已提交狀態
  //                  （OrderService.java:101-103、:124-126）。
  //   - readVersion：同一次讀取載入 persistence context 的 @Version 值
  //                  （OrderEntity.java:85-87）。Hibernate 在 flush 時以
  //                  `UPDATE ... WHERE id = ? AND version = ?` 比對此值。
  //   - writeStatus：這個交易打算寫入的狀態（:110 或 :133）。
  type Txn = {
    order: str,
    readStatus: OrderStatus,
    readVersion: int,
    writeStatus: OrderStatus,
  }

  // ---- 模型層狀態 ----
  //
  // orders（宣告於 invariants.qnt）為「已提交」的狀態寫入序列。
  // pending 為已讀取但尚未提交的交易；同一訂單可以同時有多個，因為
  // OrderRepository 沒有 @Lock／悲觀鎖查詢，讀取不互斥。
  var pending: Set[Txn]

  // 因樂觀鎖衝突而回滾（ObjectOptimisticLockingFailureException）的訂單編號。
  // 純觀測量，用於 witness「過期寫入確實被攔下」；不對應程式欄位。
  var lockConflicts: Set[str]

  // ---- 輔助函式 ----

  // 已提交序列的最後一筆寫入（序列至少一筆；createOrder 是唯一建立入口）。
  pure def lastWrite(ws: List[StatusWrite]): StatusWrite =
    ws.nth(ws.length() - 1)

  // 訂單目前的已提交狀態。
  def currentStatus(k: str): OrderStatus =
    lastWrite(writesOf(k)).writtenStatus

  // 訂單目前的 @Version 值。Hibernate 的語意：INSERT 寫入 0，之後每次成功的
  // UPDATE 遞增 1（OrderEntity.java:85-87、docs/orders-optimistic-locking.md）。
  // 已提交寫入序列的第一筆是 INSERT，因此 version == 已提交筆數 - 1。
  def currentVersion(k: str): int =
    writesOf(k).length() - 1

  // OrderService.isPermittedTransition（OrderService.java:148-166）逐分支對照：
  //   from == to        → false（:149-151）
  //   PENDING           ← NEW（:153）
  //   CONFIRMED         ← PENDING（:154）
  //   IN_PROCESS        ← CONFIRMED（:155）
  //   SHIPPED           ← IN_PROCESS（:156）
  //   DELIVERED         ← SHIPPED（:157）
  //   CANCELLED         ← canBeCancelled(from)（:158、:138-140）
  //   ERROR             ← NEW/PENDING/CONFIRMED/IN_PROCESS（:159-163）
  //   NEW               → false（:164）
  // 這與 invariants.qnt 的 isAllowedTransition 是同一個謂詞，故直接沿用；
  // 若日後程式與規格再度分歧，這裡就要改成獨立的 as-is 謂詞。
  // （參數名用 nextStatus 而非 to：`to` 是 Quint 內建名稱，不可遮蔽。）
  pure def codePermitsTransition(from: OrderStatus, nextStatus: OrderStatus): bool =
    isAllowedTransition(from, nextStatus)

  // OrderService.canBeCancelled（OrderService.java:138-140）。
  pure def codeCanBeCancelled(s: OrderStatus): bool =
    canCancelFrom(s)

  // ---- State machine ----

  // 初始狀態：沒有任何訂單、沒有進行中的交易、沒有樂觀鎖衝突。
  action init: bool = all {
    orders' = Map(),
    pending' = Set(),
    lockConflicts' = Set(),
  }

  // createOrder（OrderService.java:35-58）：
  //   - orderNumber 為空時以 UUID 產生（:36-38）；模型以符號編號取代。
  //   - status == null → 設為 NEW（:40-41）；
  //     status != null 且 != NEW → 拋 InvalidOrderException（:42-44），
  //     交易不提交、資料庫沒有任何寫入。
  //   因此「已提交的建立寫入」必為 NEW；被拒絕的路徑沒有可觀測的狀態變化，
  //   不建模為步驟（避免在模型裡加入程式不會產生的 stutter）。
  //   - save 為 INSERT，@Version 由 Hibernate 初始化為 0（version 欄位為 Long，
  //     未持久化時為 null，故 Spring Data 判定為新實體）。
  action createOrder(k: str): bool = all {
    not(orders.keys().contains(k)),
    orders' = orders.put(k, { writes: List({ readStatus: NEW, writtenStatus: NEW }) }),
    pending' = pending,
    lockConflicts' = lockConflicts,
  }

  // updateOrderStatus 的第一段（OrderService.java:100-111）：
  //   findByOrderNumber 讀取現況（:101-103），不存在則拋 OrderNotFoundException；
  //   以「讀到的 oldStatus」檢查 isPermittedTransition（:105-109），不通過則拋
  //   IllegalStateException、交易不提交（模型不建立 pending）；
  //   通過後 setStatus + save（:110-111），實際 UPDATE 發生在提交時。
  action beginUpdate(k: str, s: OrderStatus): bool = all {
    orders.keys().contains(k),
    codePermitsTransition(currentStatus(k), s),
    pending' = pending.union(Set({
      order: k,
      readStatus: currentStatus(k),
      readVersion: currentVersion(k),
      writeStatus: s,
    })),
    orders' = orders,
    lockConflicts' = lockConflicts,
  }

  // cancelOrder 的第一段（OrderService.java:123-136）：
  //   讀取現況（:124-126）後檢查 canBeCancelled（:128-131），不在 NEW／PENDING
  //   則拋 IllegalStateException、交易不提交；通過後寫入 CANCELLED（:133-134）。
  action beginCancel(k: str): bool = all {
    orders.keys().contains(k),
    codeCanBeCancelled(currentStatus(k)),
    pending' = pending.union(Set({
      order: k,
      readStatus: currentStatus(k),
      readVersion: currentVersion(k),
      writeStatus: CANCELLED,
    })),
    orders' = orders,
    lockConflicts' = lockConflicts,
  }

  // 提交成功：Hibernate 的 `UPDATE ... SET status = ?, version = version + 1
  // WHERE id = ? AND version = ?` 命中 1 列，亦即讀取後沒有其他交易提交過。
  action commit(txn: Txn): bool = all {
    pending.contains(txn),
    orders.keys().contains(txn.order),
    txn.readVersion == currentVersion(txn.order),
    orders' = orders.put(txn.order, {
      writes: writesOf(txn.order).append({
        readStatus: txn.readStatus,
        writtenStatus: txn.writeStatus,
      }),
    }),
    pending' = pending.exclude(Set(txn)),
    lockConflicts' = lockConflicts,
  }

  // 提交失敗：版本已被其他交易遞增，versioned UPDATE 命中 0 列，Spring 轉譯為
  // ObjectOptimisticLockingFailureException（OrderEntity.java:79-87、
  // docs/orders-optimistic-locking.md）。交易回滾，資料庫沒有任何寫入。
  action abortOnStaleVersion(txn: Txn): bool = all {
    pending.contains(txn),
    orders.keys().contains(txn.order),
    txn.readVersion != currentVersion(txn.order),
    orders' = orders,
    pending' = pending.exclude(Set(txn)),
    lockConflicts' = lockConflicts.union(Set(txn.order)),
  }

  // ---- 非決定選擇 ----

  action createAction: bool = {
    nondet k = ORDER_IDS.oneOf()
    createOrder(k)
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

  action abortAction: bool = {
    nondet txn = pending.oneOf()
    abortOnStaleVersion(txn)
  }

  action step: bool = any {
    createAction,
    updateAction,
    cancelAction,
    commitAction,
    abortAction,
  }

  // ---- 情境 witness（每條 INV_* 至少一個）----
  //
  // 全部以正面敘述書寫：描述「該不變量要保護的情境確實發生過」。
  // 不是不變量的否定，且在初始狀態（orders、pending、lockConflicts 皆空）全部不成立。

  // INV_newOrderStartsNew：確實有訂單被建立並提交（建立寫入為 NEW）。
  val WIT_orderCreatedAsNew: bool =
    orders.keys().exists(k => writesOf(k).nth(0).writtenStatus == NEW)

  // INV_normalFlowIsSingleStep：確實發生過一次正常流程的前進（相鄰兩筆正常狀態、階數 +1）。
  val WIT_normalForwardStep: bool =
    orders.keys().exists(k =>
      adjacentIndices(k).exists(i =>
        isNormalStatus(writesOf(k).nth(i).writtenStatus)
          and isNormalStatus(writesOf(k).nth(i + 1).writtenStatus)
          and normalRank(writesOf(k).nth(i + 1).writtenStatus)
            == normalRank(writesOf(k).nth(i).writtenStatus) + 1))

  // INV_normalFlowIsSingleStep（第二個情境）：確實有訂單走完整條正常流程
  // 到 DELIVERED（NEW → PENDING → CONFIRMED → IN_PROCESS → SHIPPED → DELIVERED
  // 共 5 次轉移，加上建立至少需要 11 個步驟）。
  val WIT_deliveredReached: bool =
    orders.keys().exists(k => currentStatus(k) == DELIVERED)

  // INV_cancelOnlyFromNewOrPending：確實有一張訂單被取消並提交。
  val WIT_cancelCommitted: bool =
    orders.keys().exists(k =>
      adjacentIndices(k).exists(i =>
        writesOf(k).nth(i + 1).writtenStatus == CANCELLED))

  // INV_errorOnlyFromAllowed：確實有一張訂單進入 ERROR 並提交。
  val WIT_errorCommitted: bool =
    orders.keys().exists(k =>
      adjacentIndices(k).exists(i =>
        writesOf(k).nth(i + 1).writtenStatus == ERROR))

  // INV_onlyPermittedTransitions：確實發生過狀態轉移（已提交序列不只建立那一筆）。
  val WIT_statusTransitionCommitted: bool =
    orders.keys().exists(k => writesOf(k).length() > 1)

  // INV_onlyPermittedTransitions（第二個情境）：確實有訂單走到終態，
  // 也就是「終態不得再轉移」這條規則真的被觸及過。
  val WIT_terminalStateReached: bool =
    orders.keys().exists(k => {
      val s = currentStatus(k)
      s == DELIVERED or s == CANCELLED or s == ERROR
    })

  // INV_committedWritesAreSequentialAndFresh：兩個交易同時爭取同一張訂單
  // （同一訂單上有 2 個以上尚未提交的交易）。
  val WIT_concurrentTxnsOnSameOrder: bool =
    ORDER_IDS.exists(k =>
      pending.filter(t => t.order == k).size() >= 2)

  // INV_committedWritesAreSequentialAndFresh（第二個情境）：有交易握著過期讀取
  // （它讀到的版本已被別人遞增），亦即「以過期讀取覆寫」的前置條件確實出現。
  val WIT_staleReaderExists: bool =
    pending.exists(t =>
      orders.keys().contains(t.order) and t.readVersion < currentVersion(t.order))

  // INV_committedWritesAreSequentialAndFresh（第三個情境）：樂觀鎖確實攔下了
  // 一次過期寫入（交易回滾、資料庫未被覆寫）。
  val WIT_staleWriteRejected: bool =
    lockConflicts != Set()
}
