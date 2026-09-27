# OpenAPI Documentation for Orders Service

## Overview

This service provides OpenAPI 3.0 / Swagger documentation for its HTTP REST endpoints using SpringDoc.

> [!NOTE]
> **Primary API Architecture**: Inter-service communication for orders has migrated to **gRPC** (`OrdersGrpcService`, port `9090`, contract defined in `src/main/proto/orders.proto`). The legacy Orders REST API is **deprecated** and disabled by default.

## API Endpoints

### 1. Orders API (Legacy / Backward Compatibility)

> [!IMPORTANT]
> The Orders REST controller is protected by `@ConditionalOnProperty(name = "orders.rest.enabled", havingValue = "true")`.
> To view and access `/api/orders` endpoints in Swagger UI, you must start the service with:
> ```bash
> export ORDERS_REST_ENABLED=true
> ./mvnw spring-boot:run
> ```

- `POST /api/orders` - Create a new order
- `GET /api/orders` - Get all orders (paginated)
- `GET /api/orders/{orderNumber}` - Get order by unique order number

### 2. Cart API (Active)

The Cart API is enabled by default for session-based shopping cart management:

- `GET /api/cart` - Retrieve current cart from session
- `POST /api/cart/items` - Add product item to cart
- `PUT /api/cart/items/{productCode}` - Update item quantity in cart

## OpenAPI Endpoints

Once the service is running, the following endpoints are available:

### OpenAPI JSON Specification
- **URL**: `http://localhost:8091/api-docs`
- **Format**: JSON
- **Description**: Raw OpenAPI 3.0 specification document

### Swagger UI
- **URL**: `http://localhost:8091/swagger-ui.html`
- **Description**: Interactive web interface for exploring and testing the REST API

## Schema Documentation

All request/response DTOs are documented with validation constraints and schemas:

### Key Schemas
- `CreateOrderRequest` - Request payload to create new orders
- `CreateOrderResponse` - Response payload after order creation
- `OrderDto` - Complete order information model
- `OrderView` - Simplified summary view for order listings
- `CartDto` - Cart contents and item details
- `AddToCartRequest` - Payload to add items to cart
- `UpdateQuantityRequest` - Payload to update cart item quantity

## Configuration

The OpenAPI documentation is configured in `OpenApiConfig.java` and `application.properties`:
- **Title**: `Orders Service API`
- **Description**: `Orders microservice extracted from the bookstore modular monolith`
- **Version**: `1.0.0`
- **Server**: `http://localhost:8091`
- Actuator endpoints are excluded from the public OpenAPI documentation (`springdoc.show-actuator=false`)

## gRPC vs OpenAPI

- **REST Endpoints**: Documented via OpenAPI 3.0 at `http://localhost:8091/swagger-ui.html`.
- **gRPC Services**: Defined in Protocol Buffers (`src/main/proto/orders.proto` and `src/main/proto/catalog.proto`), running on port `9090` with gRPC reflection enabled (`grpc.server.reflection-service-enabled=true`).