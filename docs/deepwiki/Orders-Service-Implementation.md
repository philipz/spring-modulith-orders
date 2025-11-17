# Orders Service Implementation

> **Relevant source files**
> * [src/main/java/com/sivalabs/bookstore/orders/InvalidOrderException.java](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/InvalidOrderException.java)
> * [src/main/java/com/sivalabs/bookstore/orders/OrderNotFoundException.java](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrderNotFoundException.java)
> * [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java)
> * [src/main/java/com/sivalabs/bookstore/orders/api/OrdersApi.java](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/api/OrdersApi.java)

## Purpose and Scope

This document details the implementation of the `OrdersApiService` class, which serves as the primary facade for all order-related operations in the orders-service. The `OrdersApiService` implements the `OrdersApi` interface and orchestrates the interaction between the API layer, domain layer, external services, and data transformation logic.

This page covers the internal workings of the service implementation, validation logic, and integration patterns. For architectural context of the API layer, see [API Layer Design](/philipz/spring-modulith-orders/3.3-api-layer-design). For detailed exception specifications, see [Exception Handling](/philipz/spring-modulith-orders/5.3-exception-handling). For API contract definitions, see [Request and Response Models](/philipz/spring-modulith-orders/4.3-request-and-response-models).

---

## Component Overview

The `OrdersApiService` class is a Spring-managed component (`@Component`) that implements the `OrdersApi` interface defined in the `order-api-model` named interface. It acts as an application service layer between the presentation layer (REST/gRPC) and the domain layer.

### Key Responsibilities

| Responsibility | Description |
| --- | --- |
| **API Contract Implementation** | Implements the three methods defined in `OrdersApi`: `createOrder`, `findOrder`, and `findOrders` |
| **Business Validation** | Validates order items beyond basic bean validation constraints |
| **External Integration** | Coordinates with `ProductCatalogPort` for product validation |
| **Data Transformation** | Uses `OrderMapper` to convert between API DTOs and domain entities |
| **Domain Coordination** | Delegates business logic execution to `OrderService` in the domain layer |

### Dependencies

```mermaid
flowchart TD

OrdersApiService["OrdersApiService<br>(@Component)"]
OrdersApi["«interface»<br>OrdersApi"]
OrderService["OrderService<br>(Domain Layer)"]
ProductCatalogPort["«interface»<br>ProductCatalogPort"]
OrderMapper["OrderMapper<br>(Static Utility)"]
createOrder["createOrder(CreateOrderRequest)"]
findOrder["findOrder(String)"]
findOrders["findOrders(int, int)"]

OrdersApiService --> OrdersApi
OrdersApiService --> OrderService
OrdersApiService --> ProductCatalogPort
OrdersApiService --> OrderMapper
OrdersApi --> createOrder
OrdersApi --> findOrder
OrdersApi --> findOrders
```

**Sources:** [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L17-L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L17-L26)

 [src/main/java/com/sivalabs/bookstore/orders/api/OrdersApi.java L1-L13](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/api/OrdersApi.java#L1-L13)

---

## Service Methods Implementation

### createOrder Method

The `createOrder` method implements the order creation workflow with a three-stage validation and transformation pipeline.

#### Method Signature and Flow

```mermaid
sequenceDiagram
  participant Client
  participant OrdersApiService
  participant validateOrderItem
  participant ProductCatalogPort
  participant OrderMapper
  participant OrderService

  Client->>OrdersApiService: createOrder(CreateOrderRequest)
  note over OrdersApiService: Stage 1: Bean Validation
  OrdersApiService->>validateOrderItem: validateOrderItem(item)
  note over validateOrderItem: Stage 2: Business Rules
  validateOrderItem-->>OrdersApiService: throws InvalidOrderException if invalid
  OrdersApiService->>ProductCatalogPort: validate(code, price)
  note over ProductCatalogPort: Stage 3: External Validation
  ProductCatalogPort-->>OrdersApiService: throws exception if invalid
  OrdersApiService->>OrderMapper: convertToEntity(request)
  OrderMapper-->>OrdersApiService: Order entity
  OrdersApiService->>OrderService: createOrder(Order)
  note over OrderService: Persists order,
  OrderService-->>OrdersApiService: saved Order
  OrdersApiService-->>Client: CreateOrderResponse(orderNumber)
```

#### Implementation Details

The method performs operations in this strict order:

1. **Business Validation** - Calls `validateOrderItem(request.item())` at [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L31](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L31-L31)
2. **External Validation** - Invokes `productCatalogPort.validate()` at [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L33](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L33-L33)
3. **Entity Conversion** - Transforms DTO to entity using `OrderMapper.convertToEntity()` at [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L34](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L34-L34)
4. **Domain Execution** - Delegates to `orderService.createOrder()` at [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L34](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L34-L34)
5. **Response Construction** - Wraps order number in `CreateOrderResponse` at [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L35](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L35-L35)

**Sources:** [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L28-L36](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L28-L36)

---

### findOrder Method

The `findOrder` method retrieves a single order by its order number and transforms it to a DTO.

#### Implementation Pattern

```mermaid
flowchart TD

Input["String orderNumber"]
OrderService["orderService.findOrder()"]
Optional["Optional<Order>"]
OrderMapper["OrderMapper.convertToDto()"]
Output["Optional<OrderDto>"]

Input --> OrderService
OrderService --> Optional
Optional --> OrderMapper
OrderMapper --> Output
```

The method uses Java's `Optional.map()` to perform transformation only when an order exists:

```
return orderService.findOrder(orderNumber).map(OrderMapper::convertToDto);
```

This pattern ensures:

* **Null Safety** - No explicit null checks required
* **Lazy Transformation** - DTO conversion only occurs if order exists
* **Clean Semantics** - Method signature clearly indicates optional result

**Sources:** [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L53-L56](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L53-L56)

---

### findOrders Method

The `findOrders` method implements paginated order listing with defensive parameter handling.

#### Pagination Logic

| Step | Logic | Line Reference |
| --- | --- | --- |
| **Input Sanitization** | `pageNumber = Math.max(page, 1)` ensures minimum page 1 | [59-61](https://github.com/philipz/spring-modulith-orders/blob/eb506991/59-61) |
| **Page Size Validation** | `pageSize = Math.max(size, 1)` ensures minimum size 1 | [59-61](https://github.com/philipz/spring-modulith-orders/blob/eb506991/59-61) |
| **Sort Configuration** | Orders by `id` descending (newest first) | [63](https://github.com/philipz/spring-modulith-orders/blob/eb506991/63) |
| **Zero-Based Conversion** | Converts to zero-based indexing: `pageNumber - 1` | [63](https://github.com/philipz/spring-modulith-orders/blob/eb506991/63) |
| **Domain Query** | Fetches `Page<Order>` from `orderService` | [64](https://github.com/philipz/spring-modulith-orders/blob/eb506991/64) |
| **Entity Mapping** | Transforms to `OrderView` via `OrderMapper` | [65](https://github.com/philipz/spring-modulith-orders/blob/eb506991/65) |
| **Response Construction** | Builds `PagedResult` with metadata | [66-74](https://github.com/philipz/spring-modulith-orders/blob/eb506991/66-74) |

#### PagedResult Construction

The method constructs a `PagedResult` wrapper containing:

* `content` - List of `OrderView` objects
* `totalElements` - Total count across all pages
* `pageNumber` - One-based page number (converted back from zero-based)
* `totalPages` - Total number of pages
* `isFirst`, `isLast`, `hasNext`, `hasPrevious` - Navigation flags

**Sources:** [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L58-L75](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L58-L75)

---

## Validation Pipeline

The service implements a multi-layered validation strategy that executes in a defined order.

### Validation Stages

```mermaid
flowchart TD

Request["CreateOrderRequest"]
BeanVal["@NotBlank, @Email, @Valid<br>annotations on DTOs"]
BizVal["validateOrderItem()<br>method"]
Q["quantity > 0?"]
P["price > 0?"]
C["code not blank?"]
N["name not blank?"]
ExtVal["ProductCatalogPort.validate()"]
ProdExists["Product exists?"]
PriceMatch["Price matches?"]
Success["Proceed to Order Creation"]
Fail1["InvalidOrderException"]
Fail2["ProductValidationException"]

Q --> Fail1
P --> Fail1
C --> Fail1
N --> Fail1
ProdExists --> Fail2
PriceMatch --> Fail2
PriceMatch --> Success

subgraph Stage3 ["Stage 3: External Validation"]
    ExtVal
    ProdExists
    PriceMatch
    ProdExists --> PriceMatch
end

subgraph Stage2 ["Stage 2: Business Rule Validation"]
    BizVal
    Q
    P
    C
    N
    Q --> P
    P --> C
    C --> N
end

subgraph Stage1 ["Stage 1: Framework Bean Validation"]
    BeanVal
end
```

### validateOrderItem Method Implementation

The private `validateOrderItem` method at [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L38-L51](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L38-L51)

 enforces business invariants:

| Validation Rule | Condition | Exception Message |
| --- | --- | --- |
| **Positive Quantity** | `quantity > 0` | "Quantity must be greater than 0" |
| **Positive Price** | `price.compareTo(ZERO) > 0` | "Price must be greater than 0" |
| **Code Presence** | `code != null && !code.trim().isEmpty()` | "Product code is required" |
| **Name Presence** | `name != null && !name.trim().isEmpty()` | "Product name is required" |

All validation failures throw `InvalidOrderException` with descriptive messages. The method uses explicit checks rather than annotations to provide custom error messages and enforce domain-specific rules.

**Sources:** [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L38-L51](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L38-L51)

---

## External Integration

The service integrates with external systems through the `ProductCatalogPort` interface, following the ports-and-adapters pattern.

### ProductCatalogPort Usage

```mermaid
flowchart TD

OrdersApiService["OrdersApiService"]
Port["«interface»<br>ProductCatalogPort"]
RestClient["RestClient Implementation<br>(infrastructure slice)"]
ProductCatalog["Product Catalog Service<br>(monolith:8080)"]
Note1["Dependency Inversion:<br>OrdersApiService depends on<br>abstraction, not implementation"]

OrdersApiService --> Port
Port --> RestClient
RestClient --> ProductCatalog
```

#### Integration Pattern

The `productCatalogPort.validate(request.item().code(), request.item().price())` call at [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L33](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L33-L33)

 performs:

1. **Product Existence Check** - Verifies the product code exists in the catalog
2. **Price Consistency** - Validates the submitted price matches the catalog price
3. **Exception Propagation** - Throws exceptions on validation failure (implementation-specific)

This design allows the service to:

* Remain decoupled from HTTP client implementation details
* Support multiple implementations (REST, gRPC, mock)
* Test validation logic independently via port mocking

**Sources:** [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L23-L26](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L23-L26)

 [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L33](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L33-L33)

---

## Data Transformation

The `OrdersApiService` delegates all data transformation to the `OrderMapper` utility class, maintaining separation of concerns.

### Transformation Points

```mermaid
flowchart TD

CreateReq["CreateOrderRequest"]
OrderNum["String orderNumber"]
PageParams["int page, int size"]
Order["Order entity"]
OrderPage["Page<Order>"]
CreateResp["CreateOrderResponse"]
OrderDto["OrderDto"]
OrderViewList["PagedResult<OrderView>"]

CreateReq --> Order
Order --> CreateResp
OrderNum --> Order
Order --> OrderDto
PageParams --> OrderPage
OrderPage --> OrderViewList

subgraph Output ["API DTOs"]
    CreateResp
    OrderDto
    OrderViewList
end

subgraph Domain ["Domain Entities"]
    Order
    OrderPage
end

subgraph Input ["API DTOs (order-api-model)"]
    CreateReq
    OrderNum
    PageParams
end
```

### Mapper Invocations

| Location | Transformation | Purpose |
| --- | --- | --- |
| [OrdersApiService.java L34](https://github.com/philipz/spring-modulith-orders/blob/eb506991/OrdersApiService.java#L34-L34) | `OrderMapper.convertToEntity(request)` | Converts `CreateOrderRequest` to `Order` entity |
| [OrdersApiService.java L55](https://github.com/philipz/spring-modulith-orders/blob/eb506991/OrdersApiService.java#L55-L55) | `OrderMapper::convertToDto` | Converts `Order` entity to `OrderDto` |
| [OrdersApiService.java L65](https://github.com/philipz/spring-modulith-orders/blob/eb506991/OrdersApiService.java#L65-L65) | `OrderMapper::convertToOrderView` | Converts `Order` entity to `OrderView` (lightweight) |

The service never performs direct field mapping, ensuring:

* **Single Responsibility** - Service focuses on orchestration, mapper handles transformation
* **Testability** - Mapping logic can be tested independently
* **Maintainability** - Field mapping changes isolated to `OrderMapper`

**Sources:** [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L34](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L34-L34)

 [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L55](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L55-L55)

 [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L65](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L65-L65)

---

## Exception Handling

The service throws two custom exceptions to signal different error conditions.

### Exception Types and Usage

```mermaid
flowchart TD

OrdersApiService["OrdersApiService Methods"]
InvalidOrder["InvalidOrderException"]
InvalidCases["• quantity ≤ 0<br>• price ≤ 0<br>• blank product code<br>• blank product name"]
OrderNotFound["OrderNotFoundException"]
NFCases["• Order number does not exist<br>(thrown by domain layer)"]

OrdersApiService --> InvalidOrder
OrdersApiService --> OrderNotFound

subgraph NotFound ["Lookup Failures"]
    OrderNotFound
    NFCases
    OrderNotFound --> NFCases
end

subgraph Validation ["Validation Failures"]
    InvalidOrder
    InvalidCases
    InvalidOrder --> InvalidCases
end
```

### InvalidOrderException

Thrown by `validateOrderItem()` when business validation rules fail. The exception is instantiated with descriptive messages at:

* [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L40](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L40-L40)  - Invalid quantity
* [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L43](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L43-L43)  - Invalid price
* [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L46](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L46-L46)  - Missing product code
* [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L49](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L49-L49)  - Missing product name

The exception class is a simple `RuntimeException` wrapper at [src/main/java/com/sivalabs/bookstore/orders/InvalidOrderException.java L1-L8](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/InvalidOrderException.java#L1-L8)

### OrderNotFoundException

This exception is typically thrown by the domain layer when an order lookup fails. The `OrdersApiService` does not directly throw this exception but propagates it from `OrderService.findOrder()`.

The exception provides a factory method `forOrderNumber(String)` at [src/main/java/com/sivalabs/bookstore/orders/OrderNotFoundException.java L9-L11](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrderNotFoundException.java#L9-L11)

 for standardized error messages.

Note that the `findOrder` method returns `Optional<OrderDto>` at [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L54](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L54-L54)

 so the exception is only thrown internally if the domain layer chooses to, not as part of the API contract.

**Sources:** [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L38-L51](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L38-L51)

 [src/main/java/com/sivalabs/bookstore/orders/InvalidOrderException.java L1-L8](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/InvalidOrderException.java#L1-L8)

 [src/main/java/com/sivalabs/bookstore/orders/OrderNotFoundException.java L1-L12](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrderNotFoundException.java#L1-L12)

---

## Component Interaction Summary

The following diagram shows the complete interaction model for `OrdersApiService` within the application architecture:

```mermaid
flowchart TD

RestController["OrdersController<br>(web slice)"]
GrpcService["OrderGrpcService<br>(grpc slice)"]
OrdersApi["«interface»<br>OrdersApi"]
OrdersApiService["OrdersApiService<br>(@Component)"]
OrderService["OrderService"]
Order["Order Entity"]
ProductCatalogPort["«interface»<br>ProductCatalogPort"]
RestClientImpl["RestClient Implementation"]
OrderMapper["OrderMapper<br>(Static Methods)"]
InvalidOrderException["InvalidOrderException"]
OrderNotFoundException["OrderNotFoundException"]
Note1["OrdersApiService orchestrates:<br>1. Validation (business rules)<br>2. External integration<br>3. Data transformation<br>4. Domain delegation"]

RestController --> OrdersApi
GrpcService --> OrdersApi
OrdersApiService --> ProductCatalogPort
OrdersApiService --> OrderMapper
OrdersApiService --> OrderService
OrdersApiService --> InvalidOrderException
OrderService --> OrderNotFoundException

subgraph Exceptions ["Exception Types"]
    InvalidOrderException
    OrderNotFoundException
end

subgraph Utilities ["Utilities"]
    OrderMapper
end

subgraph Infrastructure ["Infrastructure Layer"]
    ProductCatalogPort
    RestClientImpl
    ProductCatalogPort --> RestClientImpl
end

subgraph Domain ["Domain Layer (domain slice)"]
    OrderService
    Order
    OrderService --> Order
end

subgraph API ["API Layer (api slice)"]
    OrdersApi
    OrdersApiService
    OrdersApi --> OrdersApiService
end

subgraph Presentation ["Presentation Layer"]
    RestController
    GrpcService
end
```

**Sources:** [src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java L1-L77](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/OrdersApiService.java#L1-L77)

 [src/main/java/com/sivalabs/bookstore/orders/api/OrdersApi.java L1-L13](https://github.com/philipz/spring-modulith-orders/blob/eb506991/src/main/java/com/sivalabs/bookstore/orders/api/OrdersApi.java#L1-L13)