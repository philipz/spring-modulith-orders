# Overview

> **Relevant source files**
> * [README-OpenAPI.md](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-OpenAPI.md)
> * [README-deployment.md](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-deployment.md)
> * [README.md](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README.md)
> * [pom.xml](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml)
> * [src/main/java/com/sivalabs/bookstore/orders/OrdersApplication.java](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApplication.java)

This document provides a comprehensive introduction to the `orders-service`, a Spring Boot microservice extracted from a bookstore modular monolith. It explains the service's purpose, capabilities, architecture, and how it integrates with external systems.

For detailed setup and build instructions, see [Getting Started](/philipz/spring-modulith-orders/2-getting-started). For in-depth architectural patterns and design decisions, see [Architecture](/philipz/spring-modulith-orders/3-architecture). For API contracts and endpoint documentation, see [API Reference](/philipz/spring-modulith-orders/4-api-reference).

## Purpose and Scope

The `orders-service` is a standalone microservice responsible for managing customer orders within a distributed bookstore system. It provides order creation, retrieval, and querying capabilities through both REST and gRPC interfaces, maintains order state in PostgreSQL, publishes domain events to RabbitMQ, and integrates with a product catalog service for validation.

**Sources:** [README.md L1-L36](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README.md#L1-L36)

## Service Role in the Bookstore Ecosystem

```

```

The `orders-service` acts as the authoritative source for order data, exposing dual APIs for flexibility and performance. It validates order items against the product catalog, persists orders transactionally, and publishes events for downstream processing. The service maintains operational independence through caching and circuit breakers.

**Sources:** [README.md L1-L36](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README.md#L1-L36)

 [README-deployment.md L1-L91](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-deployment.md#L1-L91)

 [pom.xml L1-L315](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L1-L315)

## Key Capabilities

### Dual API Support

The service exposes two independent API interfaces:

| API Type | Port | Protocol | Use Case | Implementation |
| --- | --- | --- | --- | --- |
| REST | 8091 | HTTP/JSON | Web clients, browser-based apps | `OrdersController` in web slice |
| gRPC | 9090 | gRPC/Protobuf | High-performance service-to-service | `OrdersGrpcService` in grpc slice |

Both APIs route through the same application layer (`OrdersApiService`), ensuring consistent validation and business logic.

**Sources:** [README.md L20](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README.md#L20-L20)

 [README-OpenAPI.md L9-L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-OpenAPI.md#L9-L26)

 [README-deployment.md L30](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-deployment.md#L30-L30)

### Event-Driven Integration

```

```

The service uses Spring Modulith's event system with `@Externalized` annotation to publish `OrderCreatedEvent` to RabbitMQ. Events are first stored in a JDBC-backed event store (`orders_events` schema) within the same transaction as domain changes, ensuring guaranteed delivery and providing an audit trail.

**Sources:** [pom.xml L129-L156](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L129-L156)

 [README-deployment.md L61](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-deployment.md#L61-L61)

### Distributed Caching with Fault Tolerance

The service implements a custom caching layer built on Hazelcast with circuit breaker protection via `CacheErrorHandler`. When cache operations fail consecutively, the circuit opens and requests bypass the cache, falling back to the database. This prevents cache failures from cascading to application failures.

Key classes:

* `AbstractCacheService` - Base class for cached operations
* `CacheErrorHandler` - Circuit breaker implementation for cache layer
* Hazelcast `IMap` - Distributed cache storage

**Sources:** [pom.xml L158-L177](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L158-L177)

### Historical Data Migration

The service includes a backfill mechanism to migrate historical orders from a legacy monolith database during startup. Configuration is controlled through environment variables:

* `ORDERS_BACKFILL_ENABLED` - Enable/disable backfill
* `ORDERS_BACKFILL_LOOKBACK_DAYS` - Time window for migration
* `ORDERS_BACKFILL_RECORD_LIMIT` - Maximum records per run
* `ORDERS_BACKFILL_SOURCE_URL` - Source database connection

Migration results are recorded in the `orders.backfill_audit` table for traceability and rollback support.

**Sources:** [README-deployment.md L63-L83](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-deployment.md#L63-L83)

### Comprehensive Observability

The service provides production-ready observability through:

* **Metrics**: Prometheus-compatible metrics via Micrometer on `/actuator/prometheus`
* **Tracing**: OpenTelemetry traces exported to OTLP collectors (Zipkin on port 9412)
* **Health Checks**: Spring Actuator endpoints on `/actuator/health`
* **API Documentation**: OpenAPI 3.0 specification at `/api-docs` and Swagger UI at `/swagger-ui.html`

**Sources:** [README-OpenAPI.md L1-L64](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-OpenAPI.md#L1-L64)

 [README-deployment.md L29](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-deployment.md#L29-L29)

 [pom.xml L61-L80](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L61-L80)

## Technology Stack

```

```

**Core Dependencies:**

* **Runtime**: Java 21, Spring Boot 3.5.5
* **Modularity**: Spring Modulith 1.4.3 (core, JDBC event store, AMQP externalization, actuator integration)
* **APIs**: gRPC Spring Boot Starter 2.15.0, SpringDoc OpenAPI 2.6.0
* **Persistence**: Spring Data JPA, PostgreSQL driver, Liquibase
* **Messaging**: Spring AMQP, RabbitMQ
* **Caching**: Hazelcast 5.5.6, Spring Session Hazelcast
* **Resilience**: Resilience4j 2.2.0
* **Observability**: Micrometer (Prometheus registry), OpenTelemetry OTLP exporter

**Sources:** [pom.xml L7-L238](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L7-L238)

## Internal Architecture: Spring Modulith Slices

```

```

The codebase is organized using Spring Modulith's module boundaries under `com.sivalabs.bookstore.orders`:

| Slice | Package | Purpose | Key Classes |
| --- | --- | --- | --- |
| **web** | `.web` | REST API controllers | `RestController` implementations |
| **grpc** | `.grpc` | gRPC service implementations | `OrdersGrpcService` |
| **api** | `.api` | Application service facade | `OrdersApiService`, `OrdersApi` interface |
| **domain** | `.domain` | Business logic and entities | `OrderService`, `Order`, `OrderRepository` |
| **events** | `.events` | Event definitions and publishing | `OrderCreatedEvent` with `@Externalized` |
| **infrastructure** | `.infrastructure` | External integrations and persistence | JPA repositories, `ProductCatalogPort` |
| **cache** | `.cache` | Caching abstractions and fault tolerance | `AbstractCacheService`, `CacheErrorHandler` |
| **migration** | `.migration` | Database schema management | Liquibase configuration |

This modular structure enforces architectural boundaries through Spring Modulith's compile-time verification, ensuring dependencies flow in one direction and preventing circular dependencies between slices.

**Sources:** [README.md L5-L10](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README.md#L5-L10)

 [src/main/java/com/sivalabs/bookstore/orders/OrdersApplication.java L1-L12](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApplication.java#L1-L12)

## Request Processing Flow

```

```

This sequence demonstrates how a typical order creation request flows through the Spring Modulith slices:

1. **Entry Point**: REST or gRPC controller receives the request
2. **Validation**: `OrdersApiService` performs multi-stage validation (bean validation, business rules, external validation)
3. **Transformation**: `OrderMapper` converts API DTOs to domain entities
4. **Business Logic**: `OrderService` in domain slice handles order creation
5. **Persistence**: JPA repository persists to PostgreSQL
6. **Event Publishing**: Spring Modulith stores event and externalizes to RabbitMQ
7. **Response**: Success response propagates back through the layers

**Sources:** [README.md L1-L36](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README.md#L1-L36)

 [README-OpenAPI.md L20-L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-OpenAPI.md#L20-L26)

## Integration Points

The service integrates with external systems through well-defined ports:

### ProductCatalogPort

Interface for validating product codes and prices against the product catalog service. Default target: `http://monolith:8080`.

### RabbitMQ Exchange

Publishes events to `BookStoreExchange` with routing key `orders.new`. Event consumers subscribe to this exchange for downstream processing.

### PostgreSQL Schemas

* `orders` - Primary application schema (order tables, backfill audit)
* `orders_events` - Spring Modulith event store for transactional event publishing

### Observability Endpoints

* Prometheus scrapes `/actuator/prometheus` for metrics
* OTLP collector receives traces (default: Zipkin on port 9412)

**Sources:** [README-deployment.md L26-L31](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-deployment.md#L26-L31)

 [README-deployment.md L61](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-deployment.md#L61-L61)

## Configuration and Deployment

The service follows 12-factor app principles with externalized configuration:

* **Build**: Maven with Cloud Native Buildpacks (no Dockerfile required)
* **Local Development**: Docker Compose orchestrates PostgreSQL, RabbitMQ, Zipkin, and the service
* **Kubernetes**: Manifests under `k8s/` directory with namespace isolation, secrets management, and ConfigMap-based configuration
* **Environment Variables**: All runtime configuration overridable via environment variables (see [Configuration](/philipz/spring-modulith-orders/8-configuration) for details)

For detailed deployment procedures, see [Deployment](/philipz/spring-modulith-orders/6-deployment). For build and development setup, see [Getting Started](/philipz/spring-modulith-orders/2-getting-started).

**Sources:** [README-deployment.md L1-L91](https://github.com/philipz/spring-modulith-orders/blob/eb506991/README-deployment.md#L1-L91)

 [pom.xml L274-L289](https://github.com/philipz/spring-modulith-orders/blob/eb506991/pom.xml#L274-L289)

## Next Steps

* To set up your development environment and run the service locally, proceed to [Getting Started](/philipz/spring-modulith-orders/2-getting-started)
* For architectural deep-dives into Spring Modulith organization and design patterns, see [Architecture](/philipz/spring-modulith-orders/3-architecture)
* To explore API contracts and endpoints, consult [API Reference](/philipz/spring-modulith-orders/4-api-reference)
* For testing strategies and best practices, see [Testing](/philipz/spring-modulith-orders/7-testing)