# Repository Guidelines

## Project Structure & Module Organization
- Core code lives in `src/main/java/com/sivalabs/bookstore/orders`, split by modulith slices (`domain`, `web`, `api`, `events`, `grpc`, `infrastructure`, `cache`, `migration`) so keep new components within the slice that owns the use case.
- Shared DTOs and cross-module helpers reside under `src/main/java/com/sivalabs/bookstore/common`; reuse before introducing new duplicates.
- gRPC contracts are defined in `src/main/proto/*.proto`; regenerate stubs through Maven rather than manual edits.
- Liquibase change logs stay in `src/main/resources/db`, while environment defaults land in `src/main/resources/application.properties`; test fixtures mirror this layout in `src/test/resources`.
- Tests mirror production packages in `src/test/java`; use `orders/support` for reusable test utilities and `scripts/rollback.sql` for rollbacks during manual verification.

## Build, Test & Development Commands
- `./mvnw clean verify` runs Spotless checks, compiles Proto stubs, and executes the full test suite; rely on this before pushing.
- `./mvnw spring-boot:run` starts the service on port 8091 with gRPC on 9090 using dev-friendly defaults from `application.properties`.
- `./mvnw test` executes unit and integration tests; ensure Docker is available so Testcontainers can launch Postgres and RabbitMQ.
- `./mvnw spotless:apply` formats Java sources via the Palantir style; run after structural refactors or before large reviews.

## Coding Style & Naming Conventions
- Java 21 features are allowed; keep code idiomatic and prefer records for simple DTOs.
- Spotless plus Palantir Java Format govern whitespace (4 spaces) and import ordering; avoid hand-tuning formatting or using wildcard imports.
- Classes and components follow PascalCase; Spring beans use descriptive names (`OrdersGrpcService`, `OrderMapper`), and configuration classes end with `Config`.
- Tests should end with `Tests` or `IT` to align with existing naming (`OrdersEndToEndTests`, `OrderServiceUnitTests`).

## Testing Guidelines
- Default to JUnit Jupiter with Spring Boot test slices; use AssertJ for assertions and Mockito for stubbing, matching existing patterns.
- Integration coverage depends on Testcontainers; keep suites hermetic by relying on the provided SQL fixtures in `src/test/resources/db`.
- Name test classes after the unit under test plus behavior (`OrderServiceUnitTests`); individual test methods should read as behavior statements.
- Capture new gRPC or event contracts with schema tests similar to `OrderCreatedEventSchemaTests`; update proto files and regenerate stubs in the same change set.

## Commit & Pull Request Guidelines
- The repository has no published history yet; adopt Conventional Commits (`feat:`, `fix:`, `chore:`) to keep the log searchable and CI-friendly.
- Keep commits scoped to a single cohesive change and note any configuration toggles (`ORDERS_REST_ENABLED`, ports) in the message body.
- Pull requests should summarize the feature, note affected modules, list validation commands (`./mvnw test`, curl checks), and reference tracking issues when available.
- Include screenshots or response snippets for API or UI-facing adjustments, and mention any required infrastructure updates (Rabbit queues, Liquibase changes).

## Configuration & Operations Tips
- Customize runtime behavior via environment overrides for `spring.datasource.*`, `SPRING_RABBITMQ_*`, gRPC client targets, and feature flags such as `ORDERS_REST_ENABLED`.
- Actuator endpoints are exposed at `/actuator`; enable Prometheus scraping and tracing exporters by configuring OTLP settings (`OTLP_ENDPOINT`) before deploying.
- Keep cache sizing and resilience settings (`BOOKSTORE_CACHE_*`, `resilience4j.circuitbreaker.*`) aligned with production capacity to avoid inconsistent test outcomes.
