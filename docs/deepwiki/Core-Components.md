# Core Components

> **Relevant source files**
> * [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java)
> * [src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java)

This document details the internal implementation of the key service components that form the foundation of the orders-service application. These components include the primary service implementation (`OrdersApiService`), the distributed caching infrastructure (`AbstractCacheService`), and the exception handling mechanisms.

For information about the API layer design and contracts, see [API Layer Design](/philipz/spring-modulith-orders/3.3-api-layer-design). For deployment-specific data migration components, see [Data Migration and Backfill](/philipz/spring-modulith-orders/6.3-data-migration-and-backfill). For architectural patterns and resilience strategies, see [Resilience and Fault Tolerance](/philipz/spring-modulith-orders/3.5-resilience-and-fault-tolerance).

---

## OrdersApiService Implementation

`OrdersApiService` is the central implementation of the `OrdersApi` interface, serving as the facade for all order-related operations. This component orchestrates the complete request processing pipeline, including validation, external service integration, domain logic invocation, and data transformation.

### Class Structure and Dependencies

[src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L17-L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L17-L26)

The service maintains two core dependencies:

* `OrderService` - Domain service for order business logic and persistence
* `ProductCatalogPort` - Port interface for validating product information against an external catalog

This design follows the ports-and-adapters pattern, with `ProductCatalogPort` serving as an anti-corruption layer between the orders domain and external product catalog system.

### Operation Flow

```

```

**Diagram: Order Creation Request Flow through OrdersApiService**

Sources: [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L28-L36](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L28-L36)

### Public API Methods

| Method | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| `createOrder` | `CreateOrderRequest` | `CreateOrderResponse` | Creates a new order after validation |
| `findOrder` | `String orderNumber` | `Optional<OrderDto>` | Retrieves a single order by order number |
| `findOrders` | `int page, int size` | `PagedResult<OrderView>` | Retrieves paginated list of orders |

Sources: [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L28-L75](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L28-L75)

### Validation Pipeline

The service implements a three-stage validation strategy:

**Stage 1: Bean Validation** - Framework-level validation using annotations like `@NotBlank`, `@Email`, etc. on the `CreateOrderRequest` DTO fields.

**Stage 2: Business Rule Validation** - The `validateOrderItem` method enforces domain-specific constraints:

[src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L38-L51](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L38-L51)

Validation rules enforced:

* Quantity must be greater than 0
* Price must be greater than 0
* Product code is required and non-empty
* Product name is required and non-empty

**Stage 3: External Validation** - Delegates to `ProductCatalogPort` to verify product code and price against the external catalog:

[src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L33](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L33-L33)

This ensures data consistency across service boundaries and prevents orders for non-existent or incorrectly-priced products.

### Data Transformation

The service uses `OrderMapper` to handle bidirectional transformation between API layer DTOs and domain entities:

* **Request to Entity**: `OrderMapper.convertToEntity(CreateOrderRequest)` - [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L34](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L34-L34)
* **Entity to DTO**: `OrderMapper.convertToDto(Order)` - [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L55](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L55-L55)
* **Entity to View**: `OrderMapper.convertToOrderView(Order)` - [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L65](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L65-L65)

This separation maintains clean boundaries between API contracts and domain models, allowing independent evolution of each layer.

### Pagination Handling

The `findOrders` method implements defensive pagination logic:

[src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L59-L74](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L59-L74)

Key behaviors:

* Page numbers and sizes are normalized to minimum value of 1
* Results are sorted by ID in descending order (newest first)
* Spring Data's `PageRequest` is created with 0-based indexing internally
* Response converts back to 1-based page numbers for API consumers
* Includes pagination metadata: `totalElements`, `totalPages`, `first`, `last`, `hasNext`, `hasPrevious`

Sources: [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L1-L77](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L1-L77)

---

## Caching Layer

The caching infrastructure is built on `AbstractCacheService`, a template base class that provides standardized cache operations with integrated resilience patterns. All cache implementations in the system extend this base class to inherit consistent error handling, health monitoring, and circuit breaker functionality.

### Architecture Overview

```

```

**Diagram: Caching Layer Component Structure**

Sources: [src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L7-L21](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L7-L21)

### Class Definition and Generics

[src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L7-L21](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L7-L21)

The class uses three generic type parameters:

* `K` - Key type for cache entries
* `V` - Value type for cache entries
* `Object` - Hazelcast IMap stores values as Object type for flexibility

### Core Dependencies

| Dependency | Type | Purpose |
| --- | --- | --- |
| `cache` | `IMap<K, Object>` | Hazelcast distributed map for cache storage |
| `errorHandler` | `CacheErrorHandler` | Circuit breaker and error handling wrapper |
| `valueType` | `Class<V>` | Runtime type information for safe casting |

Sources: [src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L11-L13](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L11-L13)

### Cache Operations with Resilience

All cache operations are wrapped by `CacheErrorHandler` to provide fault tolerance. The error handler implements a circuit breaker pattern that transitions between states based on consecutive failures.

#### Health Monitoring

[src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L48-L61](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L48-L61)

The `isHealthy()` method performs an active health check by:

1. Creating a health check key via the abstract `createHealthCheckKey()` method
2. Writing a test value to the cache
3. Reading back the value
4. Removing the test entry
5. Verifying the read value matches the written value

This operation is wrapped by `CacheErrorHandler.checkCacheHealth()`, which participates in circuit breaker state management.

#### Cache Statistics

[src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L23-L46](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L23-L46)

The `getCacheStats()` method retrieves comprehensive statistics including:

* Cache name and size
* Owned entry count (entries this node owns)
* Backup entry count (replicated entries)
* Hit count
* Get and Put operation counts

The method uses `errorHandler.executeWithFallback()` to return a safe fallback message if cache access fails.

#### Circuit Breaker Status

[src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L63-L72](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L63-L72)

Provides visibility into the circuit breaker state:

* Current circuit state (OPEN/CLOSED)
* Error statistics from the `CacheErrorHandler`

#### Fallback Decision Logic

[src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L78-L84](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L78-L84)

The `shouldFallbackToDatabase()` method determines whether an operation should bypass the cache and go directly to the database:

* Returns `true` immediately if the circuit breaker is open
* Delegates to `CacheErrorHandler.shouldFallbackToDatabase()` for operation-specific decisions

This enables graceful degradation when cache operations are experiencing issues.

### Protected Template Methods

The base class provides protected methods for subclasses to implement caching logic:

#### Entity Caching

[src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L147-L154](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L147-L154)

`cacheEntity(K key, V entity)` - Stores an entity in the cache with null-safety checks. Returns `true` if successful.

#### Entity Updates

[src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L156-L173](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L156-L173)

`updateCachedEntity(K key, V entity)` - Updates an existing cached entity. Only performs the update if the key exists in cache.

#### Type-Safe Casting

[src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L175-L188](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L175-L188)

`safeCast(Object cachedValue, K key)` - Performs runtime type checking and casting of cached values:

* Returns `null` if cached value is `null`
* Logs warning and returns `null` if type mismatch detected
* Returns properly typed value if validation succeeds

This prevents `ClassCastException` and provides diagnostic logging for cache data corruption issues.

### Cache Maintenance Operations

| Operation | Method | Description |
| --- | --- | --- |
| Existence Check | `existsInCache(K)` | Checks if a key exists without retrieving the value |
| Removal | `removeFromCache(K)` | Removes an entry from the cache |
| Warm-up | `warmUpCache(Iterable<K>)` | Pre-loads cache entries for specified keys |
| Circuit Reset | `resetCircuitBreaker()` | Manually resets circuit breaker state (for recovery/testing) |

Sources: [src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L97-L145](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L97-L145)

### Abstract Methods for Subclasses

Concrete cache implementations must provide:

```
protected abstract String getCacheDisplayName();
protected abstract K createHealthCheckKey();
```

* `getCacheDisplayName()` - Returns human-readable name for logging and statistics
* `createHealthCheckKey()` - Creates a unique key for health check operations

Sources: [src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L190-L192](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L190-L192)

### Integration with CacheErrorHandler

```

```

**Diagram: Cache Operation Flow with Circuit Breaker Protection**

All cache operations follow this pattern, ensuring that cache failures do not cascade to application failures. The circuit breaker provides fast-fail behavior when cache is consistently unavailable, and automatic recovery attempts when the circuit enters half-open state.

Sources: [src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java L1-L194](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/cache/AbstractCacheService.java#L1-L194)

---

## Exception Handling

The orders-service defines custom exceptions that represent specific error conditions in the order processing domain. These exceptions are used throughout the validation and business logic layers to provide meaningful error messages to API consumers.

### Custom Exception Types

**InvalidOrderException**

Thrown when an order or order item fails business validation rules. This exception is raised by:

* [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L40](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L40-L40)  - Invalid quantity
* [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L43](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L43-L43)  - Invalid price
* [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L46](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L46-L46)  - Missing product code
* [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L49](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L49-L49)  - Missing product name

**OrderNotFoundException**

Thrown when a requested order cannot be found by order number. Used in query operations where order existence is required.

### Usage Patterns

The exceptions follow a consistent pattern:

1. **Validation Context** - Thrown during the validation stage before domain logic execution
2. **Descriptive Messages** - Each exception includes a specific message describing the validation failure
3. **Early Failure** - Validation exceptions are thrown immediately upon detection, preventing invalid data from reaching domain logic

### Error Propagation Flow

```

```

**Diagram: Exception Propagation from Validation to Client**

The framework's exception handling mechanism (configured in the web and grpc slices) intercepts these exceptions and transforms them into appropriate HTTP status codes (REST) or gRPC status codes before returning to the client.

Sources: [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L38-L51](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L38-L51)

---

## Component Integration Summary

The core components work together to provide a robust, fault-tolerant order processing system:

| Component | Primary Responsibility | Key Integration Points |
| --- | --- | --- |
| `OrdersApiService` | Request orchestration and validation | → `OrderService`, `ProductCatalogPort`, `OrderMapper` |
| `AbstractCacheService` | Distributed caching with resilience | → `Hazelcast IMap`, `CacheErrorHandler` |
| `InvalidOrderException` | Business validation errors | ← `OrdersApiService.validateOrderItem()` |
| `OrderNotFoundException` | Query failure representation | ← Domain layer query operations |

These components form the foundation upon which the web and gRPC presentation layers (see [REST API](/philipz/spring-modulith-orders/4.1-rest-api) and [gRPC API](/philipz/spring-modulith-orders/4.2-grpc-api)) expose functionality to external consumers, while the domain layer (organized in the domain slice, see [Spring Modulith Organization](/philipz/spring-modulith-orders/3.2-spring-modulith-organization)) implements the core business logic.