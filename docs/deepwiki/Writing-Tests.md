# Writing Tests

> **Relevant source files**
> * [AGENTS.md](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md)
> * [lightweight-test-example.md](https://github.com/philipz/spring-modulith-orders/blob/eb506991/lightweight-test-example.md)
> * [pom.xml](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml)

This page documents practical guidelines for writing tests in the orders-service codebase, including naming conventions, Testcontainers setup, SQL fixtures, schema tests, and reusable test utilities. For an overview of the testing strategy and performance considerations, see [Testing Strategy](/philipz/spring-modulith-orders/7.1-testing-strategy).

## Test Naming Conventions

The codebase follows specific naming patterns to distinguish between different test types:

* **Unit tests**: Classes suffixed with `Tests` (e.g., `OrderServiceUnitTests`)
* **Integration tests**: Classes suffixed with `IT` (e.g., `OrdersEndToEndIT`)

Individual test methods should read as behavior statements that describe what is being tested. The test class name should reflect the unit under test plus the behavior being verified.

**Examples:**

* `OrdersApiServiceTests` - Unit tests for `OrdersApiService`
* `OrderRepositoryTests` - Integration tests for repository layer
* `OrdersEndToEndIT` - Full integration tests across all layers

Sources: [AGENTS.md L20](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L20-L20)

 [AGENTS.md L25](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L25-L25)

## Test Organization and Structure

```mermaid
flowchart TD

PROD_ORDERS["com.sivalabs.bookstore.orders"]
PROD_DOMAIN["orders/domain"]
PROD_WEB["orders/web"]
PROD_API["orders/api"]
PROD_GRPC["orders/grpc"]
PROD_EVENTS["orders/events"]
PROD_INFRA["orders/infrastructure"]
TEST_ORDERS["com.sivalabs.bookstore.orders"]
TEST_DOMAIN["orders/domain/*Tests"]
TEST_WEB["orders/web/*Tests"]
TEST_API["orders/api/*Tests"]
TEST_GRPC["orders/grpc/*IT"]
TEST_EVENTS["orders/events/*Tests"]
TEST_INFRA["orders/infrastructure/*Tests"]
TEST_SUPPORT["orders/support<br>(Reusable Utilities)"]
SQL_FIXTURES["db/*.sql<br>(SQL Fixtures)"]
TEST_PROPS["application-test.properties"]

PROD_ORDERS --> TEST_ORDERS
PROD_DOMAIN --> TEST_DOMAIN
PROD_WEB --> TEST_WEB
PROD_API --> TEST_API
PROD_GRPC --> TEST_GRPC
PROD_EVENTS --> TEST_EVENTS
PROD_INFRA --> TEST_INFRA
TEST_INFRA --> SQL_FIXTURES
TEST_GRPC --> TEST_PROPS

subgraph TEST_RESOURCES ["Test Resources (src/test/resources)"]
    SQL_FIXTURES
    TEST_PROPS
end

subgraph TEST_CODE ["Test Code (src/test/java)"]
    TEST_ORDERS
    TEST_DOMAIN
    TEST_WEB
    TEST_API
    TEST_GRPC
    TEST_EVENTS
    TEST_INFRA
    TEST_SUPPORT
    TEST_DOMAIN --> TEST_SUPPORT
    TEST_WEB --> TEST_SUPPORT
    TEST_API --> TEST_SUPPORT
    TEST_GRPC --> TEST_SUPPORT
end

subgraph PRODUCTION ["Production Code (src/main/java)"]
    PROD_ORDERS
    PROD_DOMAIN
    PROD_WEB
    PROD_API
    PROD_GRPC
    PROD_EVENTS
    PROD_INFRA
end
```

**Test Organization Principles:**

| Aspect | Pattern | Location |
| --- | --- | --- |
| **Package Structure** | Mirror production packages | `src/test/java/com/sivalabs/bookstore/orders/*` |
| **Shared Utilities** | Centralized helpers | `src/test/java/com/sivalabs/bookstore/orders/support/` |
| **Test Data** | SQL fixtures | `src/test/resources/db/` |
| **Configuration** | Test properties | `src/test/resources/application-test.properties` |
| **Rollback Scripts** | Manual verification | `scripts/rollback.sql` |

Tests mirror the production package structure, making it easy to locate tests for specific components. Reusable test utilities are consolidated in the `orders/support` directory to avoid duplication.

Sources: [AGENTS.md L4](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L4-L4)

 [AGENTS.md L7](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L7-L7)

 [AGENTS.md L8](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L8-L8)

## Testcontainers Integration

The codebase uses Testcontainers to provide real PostgreSQL and RabbitMQ instances for integration tests, ensuring tests run against production-like infrastructure.

### Container Setup Flow

```mermaid
flowchart TD

START["Test Execution Starts"]
DOCKER_CHECK["Docker<br>Available?"]
INIT_CONTAINERS["Initialize Testcontainers"]
START_PG["Start PostgreSQL Container"]
START_RABBIT["Start RabbitMQ Container"]
WAIT["Wait for Container Readiness"]
CONFIGURE["Configure Spring Datasource<br>and AMQP Properties"]
RUN_LIQUIBASE["Run Liquibase Migrations"]
LOAD_FIXTURES["Load SQL Fixtures"]
EXECUTE_TESTS["Execute Test Suite"]
CLEANUP["Cleanup Containers<br>(Automatic)"]
FAIL["Test Execution Fails"]

START --> DOCKER_CHECK
DOCKER_CHECK --> FAIL
DOCKER_CHECK --> INIT_CONTAINERS
INIT_CONTAINERS --> START_PG
INIT_CONTAINERS --> START_RABBIT
START_PG --> WAIT
START_RABBIT --> WAIT
WAIT --> CONFIGURE
CONFIGURE --> RUN_LIQUIBASE
RUN_LIQUIBASE --> LOAD_FIXTURES
LOAD_FIXTURES --> EXECUTE_TESTS
EXECUTE_TESTS --> CLEANUP
```

### Required Dependencies

The following test dependencies enable Testcontainers integration:

```xml
<!-- From pom.xml:211-225 -->
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>junit-jupiter</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>postgresql</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>rabbitmq</artifactId>
    <scope>test</scope>
</dependency>
```

### Testcontainers Usage Pattern

Integration tests requiring database access should follow this pattern:

1. **Annotate the test class** with `@SpringBootTest` and `@Testcontainers`
2. **Declare static container fields** using `@Container` annotation
3. **Configure dynamic properties** to point Spring to the container
4. **Ensure Docker is running** before executing tests

Example test structure:

* Container initialization happens once per test class
* Containers are automatically cleaned up after tests complete
* Spring Boot automatically configures datasource from container properties
* Liquibase migrations run against the containerized database

Sources: [pom.xml L210-L225](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L210-L225)

 [AGENTS.md L13](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L13-L13)

 [AGENTS.md L24](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L24-L24)

## SQL Test Fixtures

Test data is managed through SQL fixtures located in `src/test/resources/db/`, ensuring tests remain hermetic and reproducible.

### Fixture Management Strategy

```mermaid
flowchart TD

SCHEMA["Schema Setup"]
SEED_DATA["Seed Data"]
TEST_SCENARIOS["Test Scenarios"]
BEFORE["@BeforeEach<br>Load Fixtures"]
TEST["Execute Test"]
AFTER["@AfterEach<br>Cleanup"]
TRANSACTION["@Transactional<br>(Auto-Rollback)"]
CLEAN_DB["Clean Database<br>State"]

SCHEMA --> BEFORE
SEED_DATA --> BEFORE
TEST_SCENARIOS --> BEFORE
AFTER --> TRANSACTION
CLEAN_DB --> BEFORE

subgraph ISOLATION ["Test Isolation"]
    TRANSACTION
    CLEAN_DB
    TRANSACTION --> CLEAN_DB
end

subgraph TEST_LIFECYCLE ["Test Lifecycle"]
    BEFORE
    TEST
    AFTER
    BEFORE --> TEST
    TEST --> AFTER
end

subgraph FIXTURES ["SQL Fixtures (src/test/resources/db/)"]
    SCHEMA
    SEED_DATA
    TEST_SCENARIOS
end
```

### Best Practices for Test Fixtures

| Practice | Implementation | Rationale |
| --- | --- | --- |
| **Hermetic Tests** | Each test loads its own fixtures | Tests don't depend on execution order |
| **Minimal Data** | Include only data required for the test | Faster execution and clearer intent |
| **Readable Fixtures** | Use descriptive names and comments | Easy to understand test scenarios |
| **Version Control** | Keep fixtures in `src/test/resources/db/` | Track changes alongside code |
| **Liquibase Sync** | Fixtures match schema from migrations | Prevents schema mismatch errors |

Tests should rely on provided SQL fixtures rather than creating data programmatically, ensuring consistency across test runs. The Liquibase migrations (defined in `src/main/resources/db`) establish the schema, while test fixtures provide the necessary data for each test scenario.

Sources: [AGENTS.md L7](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L7-L7)

 [AGENTS.md L24](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L24-L24)

## Schema Tests for API Contracts

Schema tests verify that API contracts (gRPC, REST, and events) remain stable over time, preventing breaking changes from being introduced accidentally.

### Contract Testing Flow

```mermaid
sequenceDiagram
  participant Developer
  participant Schema Test
  participant *.proto files
  participant Event Classes
  participant API Models
  participant Contract Validator
  participant Build Pipeline

  Developer->>*.proto files: Modify gRPC contract
  Developer->>Event Classes: Update event schema
  Build Pipeline->>Schema Test: Run tests
  Schema Test->>*.proto files: Load .proto definitions
  Schema Test->>Event Classes: Serialize event
  Schema Test->>Contract Validator: Validate structure
  loop [Contract Compatible]
    Contract Validator-->>Schema Test: Pass
    Schema Test-->>Build Pipeline: Tests Pass
    Contract Validator-->>Schema Test: Fail
    Schema Test-->>Build Pipeline: Tests Fail
    Build Pipeline-->>Developer: Block merge
  end
  Developer->>API Models: Update DTOs
  Developer->>*.proto files: Regenerate stubs
  Developer->>Schema Test: Update test expectations
  Build Pipeline->>Schema Test: Re-run tests
  Schema Test-->>Build Pipeline: Pass
```

### Types of Schema Tests

**1. Event Schema Tests**

Tests like `OrderCreatedEventSchemaTests` verify that event payloads maintain their structure:

* Field names remain stable
* Data types don't change
* Required fields are present
* Serialization format is consistent

**2. gRPC Contract Tests**

Protocol Buffer definitions in `src/main/proto/*.proto` are validated through:

* Stub generation during build ([pom.xml L256-L273](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L256-L273) )
* Service interface compatibility checks
* Message structure validation
* Backwards compatibility verification

**3. REST API Schema Tests**

OpenAPI specification tests ensure:

* Request/response models match expectations
* Validation constraints are documented
* Field descriptions are accurate
* Breaking changes are caught before deployment

### Writing Schema Tests

When adding or modifying API contracts:

1. **Create schema tests** similar to `OrderCreatedEventSchemaTests`
2. **Capture the expected structure** in test assertions
3. **Update proto files** and regenerate stubs in the same changeset
4. **Document any breaking changes** in the commit message
5. **Run the full test suite** to catch downstream impacts

Schema tests act as a safety net, preventing accidental contract changes that could break downstream consumers.

Sources: [AGENTS.md L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L26-L26)

 [pom.xml L256-L273](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L256-L273)

## Test Utilities and Helpers

Reusable test utilities are centralized in the `orders/support` directory, providing common functionality across test suites.

### Test Utilities Architecture

```mermaid
flowchart TD

BASE_UNIT["BaseUnitTest<br>(Mockito Helpers)"]
BASE_INTEGRATION["BaseIntegrationTest<br>(Spring Context)"]
TEST_BUILDERS["Test Data Builders<br>(OrderTestBuilder)"]
MOCK_FACTORY["Mock Factory<br>(Common Mocks)"]
ASSERTION_HELPERS["Assertion Helpers<br>(Custom Matchers)"]
UNIT_TESTS["*Tests<br>(Unit Tests)"]
INTEGRATION_TESTS["*IT<br>(Integration Tests)"]
E2E_TESTS["*EndToEndIT"]
JUNIT["JUnit Jupiter"]
MOCKITO["Mockito"]
ASSERTJ["AssertJ"]
AWAITILITY["Awaitility"]
MOCK_WEB_SERVER["MockWebServer"]

BASE_UNIT --> UNIT_TESTS
BASE_INTEGRATION --> INTEGRATION_TESTS
BASE_INTEGRATION --> E2E_TESTS
TEST_BUILDERS --> UNIT_TESTS
TEST_BUILDERS --> INTEGRATION_TESTS
MOCK_FACTORY --> UNIT_TESTS
ASSERTION_HELPERS --> UNIT_TESTS
ASSERTION_HELPERS --> INTEGRATION_TESTS
BASE_UNIT --> MOCKITO
BASE_UNIT --> ASSERTJ
BASE_INTEGRATION --> JUNIT
MOCK_FACTORY --> MOCK_WEB_SERVER
E2E_TESTS --> AWAITILITY

subgraph EXTERNAL_LIBS ["External Libraries"]
    JUNIT
    MOCKITO
    ASSERTJ
    AWAITILITY
    MOCK_WEB_SERVER
end

subgraph TEST_TYPES ["Test Classes"]
    UNIT_TESTS
    INTEGRATION_TESTS
    E2E_TESTS
end

subgraph SUPPORT ["orders/support (Test Utilities)"]
    BASE_UNIT
    BASE_INTEGRATION
    TEST_BUILDERS
    MOCK_FACTORY
    ASSERTION_HELPERS
end
```

### Available Test Dependencies

The codebase provides comprehensive testing libraries:

| Library | Purpose | Usage |
| --- | --- | --- |
| **JUnit Jupiter** | Test framework | Annotations like `@Test`, `@BeforeEach` |
| **Mockito** | Mocking framework | Create mocks with `@Mock`, `@InjectMocks` |
| **AssertJ** | Fluent assertions | Readable assertions like `assertThat(x).isEqualTo(y)` |
| **MockMvc** | REST API testing | Test REST controllers without HTTP |
| **MockWebServer** | HTTP stub server | Mock external HTTP services |
| **Awaitility** | Async assertions | Wait for async operations with `await().until()` |
| **Testcontainers** | Infrastructure | PostgreSQL, RabbitMQ containers |

### Common Testing Patterns

**Test Data Builders**

Use builder patterns to create test objects:

* Provide sensible defaults
* Allow selective customization
* Improve test readability
* Reduce duplication

**Mock Factories**

Centralize mock creation for frequently-used dependencies:

* `ProductCatalogPort` mocks for product validation
* Repository mocks for database operations
* Event publisher mocks for async operations

**Custom Assertions**

Create domain-specific assertion helpers:

* Order state assertions
* Event payload validators
* Error response matchers

**Async Testing with Awaitility**

For event-driven tests, use Awaitility to wait for asynchronous operations:

* Poll until condition is met
* Timeout after specified duration
* Fail with descriptive messages

Sources: [pom.xml L203-L237](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L203-L237)

 [AGENTS.md L8](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L8-L8)

 [AGENTS.md L23](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L23-L23)

 [AGENTS.md L25](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L25-L25)

## Test Execution and Verification

### Running Tests

| Command | Scope | Purpose |
| --- | --- | --- |
| `./mvnw test` | All tests | Execute unit and integration tests |
| `./mvnw verify` | Full build | Run tests + Spotless + packaging |
| `./mvnw test -Dtest=OrdersApiServiceTests` | Single class | Run specific test class |
| `./mvnw test -Dtest=*IT` | Integration only | Run only integration tests |

**Prerequisites:**

* Docker must be running (for Testcontainers)
* Sufficient memory allocated to Docker (≥2GB recommended)
* PostgreSQL and RabbitMQ ports available (dynamically allocated)

### Test Execution Pipeline

```mermaid
flowchart TD

START["mvnw test"]
SPOTLESS["Spotless Check<br>(Code Formatting)"]
PROTOBUF["Protobuf Compilation<br>(gRPC Stubs)"]
COMPILE["Java Compilation"]
UNIT["Unit Tests<br>(*Tests)"]
INTEGRATION["Integration Tests<br>(*IT)"]
REPORT["Test Report<br>Generation"]
SUCCESS["Build Success"]
FAILURE["Build Failure"]

START --> SPOTLESS
SPOTLESS --> PROTOBUF
PROTOBUF --> COMPILE
COMPILE --> UNIT
UNIT --> INTEGRATION
UNIT --> FAILURE
INTEGRATION --> REPORT
INTEGRATION --> FAILURE
REPORT --> SUCCESS
```

### Debugging Test Failures

When tests fail:

1. **Check Docker status**: Ensure Docker daemon is running
2. **Review container logs**: Testcontainers output appears in test logs
3. **Verify fixtures**: Ensure SQL fixtures are compatible with schema
4. **Check isolation**: Confirm tests don't share state
5. **Run individually**: Isolate failures by running single test classes

The test suite is designed to be hermetic, meaning each test can run independently without side effects from other tests.

Sources: [AGENTS.md L11](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L11-L11)

 [AGENTS.md L13](https://github.com/philipz/spring-modulith-orders/blob/eb506991/AGENTS.md#L13-L13)

 [pom.xml L247-L314](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L247-L314)