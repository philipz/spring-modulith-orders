# Testing

> **Relevant source files**
> * [AGENTS.md](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md)
> * [lightweight-test-example.md](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md)

This document describes the comprehensive testing strategy, patterns, and best practices for the orders-service. It covers the testing pyramid approach, test infrastructure setup, naming conventions, and execution patterns used throughout the codebase.

For deployment-specific testing considerations, see [Deployment](/philipz/spring-modulith-orders/6-deployment). For configuration of test environments, see [Configuration](/philipz/spring-modulith-orders/8-configuration).

---

## Purpose and Scope

The orders-service employs a multi-layered testing strategy designed to balance coverage with execution speed. Tests are categorized by their scope and dependencies, ranging from fast unit tests that verify individual components in isolation, to integration tests that validate database interactions and message publishing, to end-to-end tests that exercise the complete system with real infrastructure.

The testing approach emphasizes:

* **Lightweight dependencies** over heavyweight test frameworks to minimize execution time
* **Testcontainers** for integration tests requiring real PostgreSQL and RabbitMQ instances
* **Hermetic test suites** using SQL fixtures for predictable, repeatable results
* **Contract tests** for gRPC and event schemas to prevent breaking changes

---

## Testing Pyramid

The codebase follows an 80/15/5 testing pyramid that optimizes for fast feedback while ensuring comprehensive coverage:

```mermaid
flowchart TD

E2E["End-to-End Tests (5%)<br>@SpringBootTest<br>Full application context<br>Execution time: ~30s per test"]
INT["Integration Tests (15%)<br>@DataJpaTest, @WebMvcTest<br>Minimal Spring context<br>Execution time: ~5s per test"]
UNIT["Unit Tests (80%)<br>@ExtendWith(MockitoExtension)<br>No Spring context<br>Execution time: <100ms per test"]

E2E --> INT
INT --> UNIT
```

**Testing Pyramid Distribution**

| Test Type | Percentage | Framework | Context | Typical Execution Time |
| --- | --- | --- | --- | --- |
| Unit Tests | 80% | JUnit Jupiter + Mockito | No Spring | < 100ms |
| Integration Tests | 15% | Spring Test Slices | Minimal Spring | < 5s |
| End-to-End Tests | 5% | SpringBootTest | Full application | < 30s |

Sources: [lightweight-test-example.md L42-L72](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md#L42-L72)

---

## Test Infrastructure and Dependencies

### Dependency Strategy

The orders-service uses a **lightweight testing approach** that avoids the monolithic `spring-boot-starter-test` dependency in favor of explicitly declared, minimal dependencies. This reduces test execution time and dependency footprint.

```mermaid
flowchart TD

JUNIT["junit-jupiter"]
MOCKITO["mockito-junit-jupiter"]
ASSERTJ["assertj-core"]
TC["testcontainers<br>(integration only)"]
SPRING_TEST["spring-test<br>(integration only)"]
BOOT_TEST["spring-boot-starter-test<br>(~15MB)"]
UNIT_TEST["Unit Tests<br>(80%)"]
INT_TEST["Integration Tests<br>(15%)"]
E2E_TEST["E2E Tests<br>(5%)"]

UNIT_TEST --> JUNIT
UNIT_TEST --> MOCKITO
UNIT_TEST --> ASSERTJ
INT_TEST --> JUNIT
INT_TEST --> TC
INT_TEST --> SPRING_TEST
E2E_TEST --> SPRING_TEST
E2E_TEST --> TC

subgraph Avoided ["Avoided Dependency"]
    BOOT_TEST
end

subgraph Lightweight ["Lightweight Test Dependencies"]
    JUNIT
    MOCKITO
    ASSERTJ
    TC
    SPRING_TEST
end
```

**Dependency Size Comparison**

| Approach | Total Size | Build Time Impact |
| --- | --- | --- |
| spring-boot-starter-test | ~15MB | Baseline |
| JUnit 5 + Mockito + AssertJ | ~3MB | 10x faster unit tests |
| Pure JUnit 5 | ~1MB | Minimal |

Sources: [lightweight-test-example.md L1-L40](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md#L1-L40)

 [lightweight-test-example.md L149-L154](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md#L149-L154)

---

## Test Infrastructure Components

```mermaid
flowchart TD

MAVEN["Maven Test Goal<br>./mvnw test"]
DOCKER_CHECK["Docker Availability Check"]
TC_INIT["Testcontainers Initialization"]
PG_CONTAINER["PostgreSQL Container<br>Testcontainers"]
RABBIT_CONTAINER["RabbitMQ Container<br>Testcontainers"]
SQL_FIXTURES["SQL Fixtures<br>src/test/resources/db"]
TEST_UTILS["Test Utilities<br>orders/support"]
UNIT["Unit Tests<br>*Tests.java<br>MockitoExtension"]
INTEGRATION["Integration Tests<br>*IT.java<br>DataJpaTest, WebMvcTest"]
E2E["End-to-End Tests<br>*Tests.java<br>SpringBootTest"]
SCHEMA["Schema Tests<br>*SchemaTests.java"]

DOCKER_CHECK --> UNIT
TC_INIT --> PG_CONTAINER
TC_INIT --> RABBIT_CONTAINER
PG_CONTAINER --> INTEGRATION
RABBIT_CONTAINER --> INTEGRATION
SQL_FIXTURES --> INTEGRATION
TEST_UTILS --> INTEGRATION
PG_CONTAINER --> E2E
RABBIT_CONTAINER --> E2E
UNIT --> TEST_UTILS

subgraph TestTypes ["Test Categories"]
    UNIT
    INTEGRATION
    E2E
    SCHEMA
    SCHEMA --> E2E
end

subgraph Infrastructure ["Test Infrastructure"]
    PG_CONTAINER
    RABBIT_CONTAINER
    SQL_FIXTURES
    TEST_UTILS
end

subgraph TestExecution ["Test Execution Flow"]
    MAVEN
    DOCKER_CHECK
    TC_INIT
    MAVEN --> DOCKER_CHECK
    DOCKER_CHECK --> TC_INIT
end
```

### Testcontainers Integration

Integration and end-to-end tests depend on **Testcontainers** to provide real PostgreSQL and RabbitMQ instances. Docker must be available on the test execution environment.

**Key characteristics:**

* Containers are started automatically before tests requiring database or messaging
* Each test class can use shared or isolated containers based on lifecycle annotations
* SQL fixtures from [src/test/resources/db](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/test/resources/db)  are applied during setup
* Containers are cleaned up after test execution

### SQL Fixtures

The [src/test/resources/db](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/test/resources/db)

 directory contains SQL scripts that establish known database states for integration tests. These fixtures ensure hermetic, repeatable test execution by providing predictable data sets.

### Test Utilities

The `orders/support` package contains reusable test utilities, base classes, and helper methods that reduce boilerplate in test code. These utilities align with the DRY principle and maintain consistency across the test suite.

Sources: [AGENTS.md L22-L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L22-L26)

 [AGENTS.md L10-L14](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L10-L14)

---

## Writing Tests

### Test Naming Conventions

Test classes follow a strict naming pattern to indicate their scope and execution profile:

| Pattern | Type | Spring Context | Infrastructure | Example |
| --- | --- | --- | --- | --- |
| `*Tests.java` | Unit or E2E | Only for E2E | None for unit | `OrderServiceUnitTests` |
| `*IT.java` | Integration | Minimal slice | Testcontainers | `OrderRepositoryIT` |
| `*SchemaTests.java` | Contract | None or minimal | None | `OrderCreatedEventSchemaTests` |

The naming convention determines:

* Build tool filtering (some CI pipelines separate unit and integration phases)
* Developer expectations about execution time
* Spring context initialization requirements

Sources: [AGENTS.md L20](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L20-L20)

 [AGENTS.md L23-L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L23-L26)

### Unit Tests (80%)

Unit tests verify individual components in isolation using mocked dependencies. They execute without Spring context initialization, making them extremely fast.

**Pattern:**

```python
@ExtendWith(MockitoExtension.class)
class OrderServiceUnitTests {
    // Test structure:
    // 1. Arrange: Create mocks and test data
    // 2. Act: Invoke method under test
    // 3. Assert: Verify behavior with AssertJ
    // 4. Verify: Check mock interactions
}
```

**Key characteristics:**

* Use `@ExtendWith(MockitoExtension.class)` instead of `@SpringBootTest`
* Execution time under 100ms per test
* AssertJ for fluent assertions
* Mockito for dependency mocking
* No database or external service dependencies

**Example test method naming:**

```
void createOrder_WithValidRequest_ReturnsOrderNumber() { }
void validateOrderItem_WithInvalidPrice_ThrowsInvalidOrderException() { }
```

Sources: [lightweight-test-example.md L44-L52](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md#L44-L52)

 [AGENTS.md L23](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L23-L23)

### Integration Tests (15%)

Integration tests validate interactions with infrastructure components like databases and message brokers, using real instances via Testcontainers.

**Pattern:**

```python
@DataJpaTest
class OrderRepositoryIT {
    // Test structure:
    // 1. Apply SQL fixtures from src/test/resources/db
    // 2. Execute repository operation
    // 3. Assert database state
}
```

**Spring Test Slices:**

| Annotation | Context Loaded | Use Case |
| --- | --- | --- |
| `@DataJpaTest` | JPA repositories, EntityManager | Repository tests |
| `@WebMvcTest` | Controllers, validators | REST API tests |
| `@SpringBootTest` | Full application context | E2E tests |

**Key characteristics:**

* Use minimal Spring context via test slices
* Testcontainers provides PostgreSQL and RabbitMQ
* SQL fixtures ensure predictable state
* Execution time under 5 seconds per test
* Suffix test classes with `IT.java` for integration tests

Sources: [lightweight-test-example.md L54-L62](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md#L54-L62)

 [AGENTS.md L24](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L24-L24)

### End-to-End Tests (5%)

End-to-end tests exercise complete business flows through the full application stack with real infrastructure.

**Pattern:**

```python
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OrdersEndToEndTests {
    // Test structure:
    // 1. Start full application with Testcontainers
    // 2. Execute REST or gRPC requests
    // 3. Verify database state, events published, cache updates
}
```

**Key characteristics:**

* Full Spring application context
* Real HTTP/gRPC endpoints on random ports
* Tests critical business paths only
* Execution time under 30 seconds per test
* Limited to 5% of test suite due to cost

Sources: [lightweight-test-example.md L64-L72](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md#L64-L72)

 [AGENTS.md L20](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L20-L20)

### Schema/Contract Tests

Schema tests validate API and event contracts to prevent breaking changes. These tests ensure that gRPC `.proto` files and published event structures remain compatible with consumers.

**Example:**

```python
class OrderCreatedEventSchemaTests {
    // Validates:
    // 1. Event field presence and types
    // 2. JSON serialization format
    // 3. Backwards compatibility
}
```

**Contract validation scope:**

* gRPC service definitions in [src/main/proto/*.proto](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/proto/*.proto)
* Event schemas for `OrderCreatedEvent` and other `@Externalized` events
* REST API request/response DTOs

When modifying contracts:

1. Update `.proto` files or event classes
2. Regenerate stubs via Maven
3. Update corresponding schema tests
4. Ensure backwards compatibility or version appropriately

Sources: [AGENTS.md L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L26-L26)

---

## Test Execution

### Maven Commands

```mermaid
flowchart TD

TEST["./mvnw test"]
VERIFY["./mvnw clean verify"]
UNIT_ONLY["./mvnw test -Dtest=*Tests"]
INT_ONLY["./mvnw test -Dtest=*IT"]
SPOTLESS["Spotless Format Check"]
PROTO_GEN["Proto Stub Generation"]
COMPILE["Compilation"]
TEST_EXEC["Test Execution"]
PACKAGE["Packaging"]

TEST --> TEST_EXEC
VERIFY --> SPOTLESS
UNIT_ONLY --> TEST_EXEC
INT_ONLY --> TEST_EXEC

subgraph Phases ["Build Phases"]
    SPOTLESS
    PROTO_GEN
    COMPILE
    TEST_EXEC
    PACKAGE
    SPOTLESS --> PROTO_GEN
    PROTO_GEN --> COMPILE
    COMPILE --> TEST_EXEC
    TEST_EXEC --> PACKAGE
end

subgraph Commands ["Maven Test Commands"]
    TEST
    VERIFY
    UNIT_ONLY
    INT_ONLY
end
```

**Standard test execution:**

```markdown
# Run all tests (unit + integration)
./mvnw test

# Run full build with formatting checks
./mvnw clean verify

# Run only unit tests
./mvnw test -Dtest=*Tests

# Run only integration tests
./mvnw test -Dtest=*IT
```

**Prerequisites:**

* Docker must be running for integration and E2E tests (Testcontainers requirement)
* JDK 21 installed
* Maven Wrapper handles Maven installation

Sources: [AGENTS.md L10-L14](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L10-L14)

### Test Execution Flow

```mermaid
sequenceDiagram
  participant Developer
  participant Maven
  participant Docker
  participant Testcontainers
  participant PostgreSQL
  participant Container
  participant RabbitMQ
  participant Test Suite

  Developer->>Maven: ./mvnw test
  Maven->>Maven: Spotless format check
  Maven->>Maven: Generate Proto stubs
  Maven->>Maven: Compile sources
  Maven->>Test Suite: Execute unit tests
  note over Test Suite: 80% of suite
  Test Suite-->>Maven: Results
  Maven->>Docker: Check availability
  Docker-->>Maven: Docker running
  Maven->>Testcontainers: Initialize containers
  Testcontainers->>PostgreSQL: Start PostgreSQL
  Testcontainers->>RabbitMQ: Start RabbitMQ
  PostgreSQL-->>Testcontainers: Container ready
  RabbitMQ-->>Testcontainers: Container ready
  Maven->>Test Suite: Execute integration tests
  note over Test Suite: 15% of suite
  Test Suite->>PostgreSQL: SQL fixtures + queries
  Test Suite->>RabbitMQ: Message publishing
  Test Suite-->>Maven: Results
  Maven->>Test Suite: Execute E2E tests
  note over Test Suite: 5% of suite
  Test Suite->>PostgreSQL: Database operations
  Test Suite->>RabbitMQ: Event publishing
  Test Suite-->>Maven: Results
  Maven->>Testcontainers: Cleanup containers
  Testcontainers->>PostgreSQL: Stop container
  Testcontainers->>RabbitMQ: Stop container
  Maven-->>Developer: Test summary
```

**Performance characteristics:**

| Suite Component | Count (approx) | Total Time |
| --- | --- | --- |
| Unit tests | 80% of total | ~10-20s |
| Integration tests | 15% of total | ~30-60s |
| E2E tests | 5% of total | ~30-90s |
| **Total** | **~100 tests** | **~2-3 minutes** |

Sources: [AGENTS.md L10-L14](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L10-L14)

 [lightweight-test-example.md L140-L148](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md#L140-L148)

---

## Test Code Organization

```mermaid
flowchart TD

DOMAIN["com.sivalabs.bookstore.orders.domain"]
WEB["com.sivalabs.bookstore.orders.web"]
API["com.sivalabs.bookstore.orders.api"]
GRPC["com.sivalabs.bookstore.orders.grpc"]
EVENTS["com.sivalabs.bookstore.orders.events"]
INFRA["com.sivalabs.bookstore.orders.infrastructure"]
DOMAIN_TEST["orders.domain.*Tests"]
WEB_TEST["orders.web.*Tests"]
API_TEST["orders.api.*Tests"]
GRPC_TEST["orders.grpc.*Tests"]
EVENTS_TEST["orders.events.*SchemaTests"]
INFRA_TEST["orders.infrastructure.*IT"]
SUPPORT["orders.support<br>(Test Utilities)"]
SQL["db/*.sql<br>(SQL Fixtures)"]
PROPS["application-test.properties"]

DOMAIN --> DOMAIN_TEST
WEB --> WEB_TEST
API --> API_TEST
GRPC --> GRPC_TEST
EVENTS --> EVENTS_TEST
INFRA --> INFRA_TEST
INFRA_TEST --> SQL
INFRA_TEST --> PROPS

subgraph Resources ["Test Resourcessrc/test/resources"]
    SQL
    PROPS
end

subgraph TestCode ["Test Codesrc/test/java"]
    DOMAIN_TEST
    WEB_TEST
    API_TEST
    GRPC_TEST
    EVENTS_TEST
    INFRA_TEST
    SUPPORT
    DOMAIN_TEST --> SUPPORT
    WEB_TEST --> SUPPORT
    API_TEST --> SUPPORT
    GRPC_TEST --> SUPPORT
    EVENTS_TEST --> SUPPORT
    INFRA_TEST --> SUPPORT
end

subgraph Production ["Production Codesrc/main/java"]
    DOMAIN
    WEB
    API
    GRPC
    EVENTS
    INFRA
end
```

**Directory structure:**

* Test packages mirror production packages in [src/test/java](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/test/java)
* Shared test utilities reside in `orders/support` package
* SQL fixtures for integration tests in [src/test/resources/db](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/test/resources/db)
* Test-specific configuration in `application-test.properties`

Sources: [AGENTS.md L8](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L8-L8)

 [AGENTS.md L24](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L24-L24)

---

## Best Practices

### Test Isolation and Hermeticity

* Each test should be independent and executable in any order
* Use SQL fixtures from [src/test/resources/db](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/test/resources/db)  to establish known state
* Clean up test data between tests or use transactional rollback
* Avoid shared mutable state across test methods

### Mocking Guidelines

* Mock external dependencies (ProductCatalogPort, external APIs)
* Use real database and messaging infrastructure via Testcontainers
* Verify mock interactions to ensure proper collaboration
* Prefer `@Mock` with `MockitoExtension` over manual `Mockito.mock()` calls

### Assertion Style

* Use AssertJ fluent assertions for readability
* Group related assertions for clear test failures
* Provide descriptive failure messages for business logic assertions
* Test both happy paths and error conditions

### Test Method Naming

Follow the pattern: `methodName_condition_expectedResult`

Examples:

* `createOrder_WithValidRequest_ReturnsOrderNumber`
* `validateOrderItem_WithNegativePrice_ThrowsInvalidOrderException`
* `findByOrderNumber_WhenNotExists_ReturnsEmpty`

### Contract Test Maintenance

When modifying public contracts:

1. Update `.proto` files or event classes
2. Run `./mvnw generate-sources` to regenerate stubs
3. Update schema tests (`OrderCreatedEventSchemaTests` and similar)
4. Verify backwards compatibility or coordinate with consumers
5. Include contract changes in the same commit as implementation

Sources: [AGENTS.md L22-L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L22-L26)

---

## Common Patterns

### Unit Test Pattern

```yaml
Class under test: OrdersApiService
Dependencies: OrderService (mocked), ProductCatalogPort (mocked), OrderMapper (real)
Test class: OrdersApiServiceTests
```

### Integration Test Pattern

```yaml
Class under test: OrderRepository
Infrastructure: PostgreSQL via Testcontainers
Fixtures: src/test/resources/db/test-data.sql
Test class: OrderRepositoryIT
```

### End-to-End Test Pattern

```yaml
Flow: REST request → Controller → Service → Repository → Database
Events: Verify OrderCreatedEvent published to RabbitMQ
Test class: OrdersEndToEndTests
```

### Schema Test Pattern

```yaml
Contract: OrderCreatedEvent
Validation: Field presence, types, JSON format, backwards compatibility
Test class: OrderCreatedEventSchemaTests
```

Sources: [AGENTS.md L20-L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L20-L26)

 [lightweight-test-example.md L44-L72](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md#L44-L72)

---

## Performance Optimization

### Minimizing Spring Context Startup

* Use `@ExtendWith(MockitoExtension.class)` for unit tests (no Spring context)
* Use test slices (`@DataJpaTest`, `@WebMvcTest`) for targeted integration tests
* Avoid `@SpringBootTest` except for critical E2E flows
* Cache Spring context between test classes when possible

### Container Reuse

* Testcontainers can reuse containers across test classes
* Configure singleton containers for PostgreSQL and RabbitMQ
* Balance container reuse with test isolation requirements

### Parallel Execution

Maven Surefire supports parallel test execution:

```markdown
./mvnw test -T 1C  # 1 thread per CPU core
```

Ensure tests are thread-safe and don't share mutable state when enabling parallelization.

Sources: [lightweight-test-example.md L140-L148](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md#L140-L148)

---

## Troubleshooting

### Docker Not Available

**Symptom:** Integration tests fail with "Could not find a valid Docker environment"

**Resolution:**

* Ensure Docker daemon is running
* Verify Docker socket permissions (Linux)
* Check Docker Desktop status (macOS/Windows)

### Testcontainers Port Conflicts

**Symptom:** Container fails to start due to port already in use

**Resolution:**

* Testcontainers automatically assigns random ports
* Ensure no conflicting services running on default ports (5432, 5672)
* Check for orphaned containers: `docker ps -a`

### SQL Fixture Issues

**Symptom:** Integration tests fail due to missing or inconsistent data

**Resolution:**

* Verify fixtures exist in [src/test/resources/db](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/test/resources/db)
* Check Liquibase changelogs have executed correctly
* Ensure test isolation (rollback transactions or clean state)

### Slow Test Execution

**Symptom:** Test suite takes significantly longer than expected

**Resolution:**

* Profile test execution to identify slow tests
* Convert slow `@SpringBootTest` tests to lighter test slices
* Check for unnecessary Testcontainers initialization
* Review mock setup complexity

Sources: [AGENTS.md L10-L14](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L10-L14)