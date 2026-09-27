<!-- factory:source-snapshot（ADR-018）：由 CI 寫入，不得修改；不變量須逐字引用本檔 -->
<!-- 來源：philipz/spring-modulith-orders#51 的「需求描述（PRD）」 · 擷取：2026-09-27T01:27:07.094Z -->

目標模組 / 檔案：src/main/java/com/sivalabs/bookstore/orders/domain/OrderService.java（規格產出於 specs/order-lifecycle/，不修改 src/）
做什麼：以本 Issue 的業務規則（下方「規格」R1–R6）為訂單生命週期建立 Quint 可執行規格——先寫不變量，經核准後再寫描述程式現況的 as-is 模型並執行模型檢查。
為什麼：訂單狀態由多個模組、多個交易同時變更；狀態轉移規則與並行交易交錯下的錯誤難以用單元測試穩定重現，可執行規格能窮盡探索狀態空間，以反例指出實作與規則不符之處。
規格：
- R1 狀態集合：NEW、PENDING、CONFIRMED、IN_PROCESS、SHIPPED、DELIVERED、CANCELLED、ERROR。新建立的訂單狀態為 NEW。
- R2 正常流程單向前進，不可跳階、不可倒退：NEW → PENDING → CONFIRMED → IN_PROCESS → SHIPPED → DELIVERED。
- R3 取消：只有 NEW、PENDING 的訂單可以轉為 CANCELLED。
- R4 錯誤：NEW、PENDING、CONFIRMED、IN_PROCESS 的訂單可以轉為 ERROR。
- R5 終態：DELIVERED、CANCELLED、ERROR 為終態，進入後不得再轉移。R2–R4 以外的轉移一律不允許。
- R6 並行：同一訂單同時有多個狀態變更時，結果必須等同於這些變更依某個順序逐一執行的結果；不得依過期的讀取覆寫狀態（例如已出貨的訂單被取消）。
範圍：
- 不變量涵蓋上方 R1–R6
- as-is 模型涵蓋 OrderService 的 createOrder、updateOrderStatus、cancelOrder，含多個交易並行執行時的讀取與寫入交錯（以 OrderEntity 與 JPA 的實際鎖定行為為準）
- 不修改 src/；找到的反例另開 agent-fix-bug 工單，由紅燈測試回放
驗證方式：
- `npx quint typecheck specs/order-lifecycle/invariants.qnt` 退出碼為 0（不變量階段）
- factory-run 依 `specs/order-lifecycle/verify.yml` 執行模型檢查，每條 INV_* 都有明確結果：成立且 witness 可達、違反並附 ITF，或逾時（模型階段）
- 單次模型檢查牆鐘 ≤ 600 秒；超過依停手規則交還人類，並回報已量測的秒數
