# 訂單並行更新與樂觀鎖

本文說明 `orders.orders` 的樂觀鎖設計（issue #58），供後續維護與呼叫端參考。

## 背景：為什麼需要

`OrderEntity` 原本沒有版本欄位。JPA 在交易提交時會以 `UPDATE ... WHERE id = ?` 覆寫整列，
因此兩個交易只要都從**同一份快照**出發，後提交者就會無聲蓋掉先提交者的變更：

- 交易 A 讀到訂單為 `PENDING`。
- 交易 B 把同一張訂單改為 `CONFIRMED` 並提交。
- 交易 A 在自己那份過期快照上改為 `CANCELLED` 並提交 → 成功，最終狀態變成 `CANCELLED`。

也就是說，已取消的訂單可能被覆寫回流程中的狀態，已出貨的訂單也可能被覆寫成取消。
issue #51 的 as-is 模型（PR #55 的 `specs/order-lifecycle/traces/` 下
`INV_committedWritesAreSequentialAndFresh` 開頭的軌跡檔）先以模型檢查找到此情境，
issue #58 再以真實資料庫上的整合測試重現並修復。

## 做法

1. `OrderEntity` 新增 `@Version` 欄位（型別為 `Long`，欄位名 `version`）。
2. Liquibase changeSet `orders-6`（`db/migration/V6__orders_add_version_column.sql`）
   為 `orders.orders` 加上 `version BIGINT NOT NULL DEFAULT 0`。
   `DEFAULT 0` 讓遷移前既有的資料列都帶有合法版本，不需另外回填。

修復後，Hibernate 的更新語句會帶上版本條件（`... WHERE id = ? AND version = ?`）並在提交時
遞增版本。上述情境中交易 A 的更新會比對到 0 列，Spring 會拋出
`org.springframework.orm.ObjectOptimisticLockingFailureException`，最終狀態維持 `CONFIRMED`。

### 回滾

`orders-6` 具備 rollback 段落（`ALTER TABLE orders.orders DROP COLUMN IF EXISTS version`），
可用 `liquibase rollbackCount 1` 或既有的回滾流程還原；程式端需同時移除 `@Version` 欄位。

## 對其他寫入路徑的影響

- **`OrderService`**：本次**未修改**。`updateOrderStatus`／`cancelOrder` 仍在同一交易內
  讀取後寫入，只是衝突時改為失敗而非覆寫。狀態轉移檢查（例如已出貨不得取消）屬另一工單。
- **`OrderMapStore`（Hazelcast write-through）**：`store`／`storeAll` 目前不寫資料庫（僅記錄
  日誌），`load`／`loadAll` 只讀取，因此加上版本欄位後行為不變。快取中的 `OrderEntity` 會
  一併帶著 `version` 序列化，重新載入後仍可正確比對版本。
- **`OrdersBackfillService`（資料遷移）**：以 `OrderEntity.builder()` 建立**新**實體，
  `version` 為 `null`，Spring Data 因此仍判定為新實體而走 `persist`，由 Hibernate 初始化為 0。
  這也是 `version` 使用包裝型別 `Long`（而非 `long`）的原因——`null` 是「尚未持久化」的標記。

## 呼叫端須知

對同一張訂單有並行寫入可能的呼叫端，需處理 `ObjectOptimisticLockingFailureException`：
重新讀取最新狀態後重試，或把衝突回報給使用者。**不要**以捕捉後忽略的方式處理，
那等於恢復成原本的覆寫行為。

## 驗證

`src/test/java/com/sivalabs/bookstore/orders/domain/OrderConcurrentUpdateIntegrationTests.java`
以 Testcontainers PostgreSQL 交錯兩個交易重現上述情境，並檢查：

- 過期快照的提交失敗（`ObjectOptimisticLockingFailureException`），且最終狀態維持 `CONFIRMED`。
- 未指定 `version` 插入的資料列讀出為 0，提交一次更新後遞增為 1。

執行方式：

```bash
./mvnw test -Dtest=OrderConcurrentUpdateIntegrationTests   # 需要 Docker
./mvnw test                                                # 全量測試
```

沒有 Docker 的環境會依 `DockerAvailability` 自動略過這組測試。
