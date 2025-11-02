# spring-modulith-orders

Spring Modulith Orders 服務是以 Spring Boot 3.5 為基礎的訂單子系統，獨立拆分自模組化單體，透過 gRPC 與其他域服務整合，並使用 Liquibase、RabbitMQ 與 Hazelcast 提供資料一致性與事件驅動能力。

## 專案結構
- `src/main/java/com/sivalabs/bookstore/orders`：以模組化 slice 分層 (`domain`, `web`, `api`, `grpc`, `events`, `infrastructure`, `cache`, `migration`)。
- `src/main/proto`：gRPC 合約；建置時由 `protobuf-maven-plugin` 產生 Java stubs。
- `src/main/resources/db`：Liquibase 變更紀錄；`application.properties` 含預設設定與可覆寫的環境變數。
- `src/test/java`：測試與支援工具，結構對應 production 套件；`src/test/resources` 提供 SQL 資料與 Mockito 設定。
- `scripts/rollback.sql`：進行資料回滾或手動驗證時使用。

## 先決條件
- JDK 21
- Docker（執行整合測試時供 Testcontainers 啟動 Postgres、RabbitMQ）
- 不需安裝 Maven，專案內建 `./mvnw` 包裝器

## 使用 Maven 建置與執行
```bash
./mvnw clean verify         # 執行 Spotless、編譯、測試與 Proto 生成
./mvnw spring-boot:run      # 啟動應用（HTTP 8091、gRPC 9090）
./mvnw package              # 產出可部署 JAR (target/orders-service-0.0.1-SNAPSHOT.jar)
```

如需自訂設定，可透過環境變數覆蓋，例如：
- `SPRING_DATASOURCE_URL`：Postgres 連線字串
- `SPRING_RABBITMQ_HOST`：RabbitMQ 主機
- `ORDERS_REST_ENABLED`：是否開啟傳統 REST API（預設關閉）

## 測試
- `./mvnw test`：執行單元測試與整合測試，依賴 Testcontainers。
- `./mvnw -Dgroups=lightweight test`：如偏好輕量測試流程，可參考 `lightweight-test-example.md` 中提供的分類範例。

## 延伸文件
- `README-OpenAPI.md`：REST 與 gRPC API 說明
- `README-deployment.md`：部署建議與觀察性設定
- `AGENTS.md`：貢獻者指南、程式碼風格與 PR 建議
