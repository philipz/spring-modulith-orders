# Orders Service Deployment Guide

This document explains how to containerize and deploy the `orders-service` independently. The service image can be produced directly by Spring Boot's Cloud Native Buildpacks support, so no custom `Dockerfile` is required.

## 1. Build Container Image

From the repository root run:

```bash
./mvnw spring-boot:build-image \
  -Dspring-boot.build-image.imageName=philipz/orders-service:latest
```

The command leverages Cloud Native Buildpacks and the configuration present in `pom.xml`. After the build completes, the image `philipz/orders-service:latest` is available locally (or pushed to the configured registry if you are logged in).

## 2. Run Locally with Docker Compose

The root `docker-compose.yml` provisions the backing infrastructure required for local development and testing:

```bash
docker compose up -d
```

Key environment bindings configured in `docker-compose.yml`:

- **PostgreSQL**: `ordersdb` exposed on host port `5432` (image: `postgres:17-alpine`)
- **RabbitMQ**: AMQP protocol on host port `5673` (mapped from 5672), management UI on `http://localhost:15672` (image: `rabbitmq:4-management-alpine`, default login: `guest`/`guest`)
- **Catalog WireMock Stub**: Mock product catalog on `http://localhost:8080` (image: `wiremock/wiremock:3.13.1`, stub definitions in `docker/catalog-stub/mappings`)

Once the infrastructure services are healthy, run the application locally:

```bash
./mvnw spring-boot:run
```

The service exposes:
- **HTTP REST / Actuator**: `http://localhost:8091`
- **gRPC Server**: `localhost:9090`

Stop the infrastructure with `docker compose down` (add `-v` to prune database volumes if needed).

## 3. Container & Kubernetes Deployment

When deploying `orders-service` to container platforms (such as Kubernetes or Docker Swarm):

1. Ensure target namespaces or network policies allow access to PostgreSQL, RabbitMQ, and the catalog service.
2. Provide required environment variables and secrets (refer to Section 4).
3. Expose service ports:
   - HTTP port `8091` (REST API & Actuator probes)
   - gRPC port `9090` (Orders gRPC service)
4. Configure container health probes:
   - **Liveness**: `http://<service-host>:8091/actuator/health/liveness`
   - **Readiness**: `http://<service-host>:8091/actuator/health/readiness`

## 4. Configuration Overview

Core runtime configuration parameters can be overridden using environment variables:

| Environment Variable | Default Value | Description |
| :--- | :--- | :--- |
| `SPRING_DATASOURCE_URL` | `jdbc:postgresql://localhost:5432/ordersdb` | PostgreSQL connection URL |
| `SPRING_DATASOURCE_USERNAME` | `postgres` | Database username |
| `SPRING_DATASOURCE_PASSWORD` | `postgres` | Database password |
| `SPRING_RABBITMQ_HOST` | `localhost` | RabbitMQ broker host |
| `SPRING_RABBITMQ_PORT` | `5673` | RabbitMQ broker port |
| `SPRING_RABBITMQ_USERNAME` | `guest` | RabbitMQ username |
| `SPRING_RABBITMQ_PASSWORD` | `guest` | RabbitMQ password |
| `SPRING_MODULITH_EVENTS_SCHEMA` | `events` | Modulith outbox event table schema |
| `OTLP_ENDPOINT` | `http://localhost:4317` | OpenTelemetry OTLP gRPC collector endpoint |
| `ORDERS_REST_ENABLED` | `false` | Enable legacy REST API (deprecated, default false) |
| `GRPC_SERVER_PORT` | `9090` | gRPC service port |
| `SERVER_PORT` | `8091` | HTTP web & actuator port |

## 5. Seed Historical Order Data

The service can backfill legacy orders from the monolith database when started:

1. Provide connection details for the source database (defaults to the service database if omitted):

   ```bash
   export ORDERS_BACKFILL_ENABLED=true
   export ORDERS_BACKFILL_LOOKBACK_DAYS=90   # Optional: limit window (default: 30)
   export ORDERS_BACKFILL_RECORD_LIMIT=500   # Maximum rows to migrate per run (default: 500)
   export ORDERS_BACKFILL_SOURCE_URL=jdbc:postgresql://monolith-db:5432/postgres
   export ORDERS_BACKFILL_SOURCE_USERNAME=postgres
   export ORDERS_BACKFILL_SOURCE_PASSWORD=postgres
   ```

2. Start the service (`./mvnw spring-boot:run` or run container). A single backfill run executes at startup and records its execution in the `orders.backfill_audit` table.
3. Reset `ORDERS_BACKFILL_ENABLED=false` after importing to avoid re-running on subsequent restarts.
4. If a rollback is required, use [`scripts/rollback.sql`](scripts/rollback.sql) with the audit ID captured in `orders.backfill_audit` to delete the migrated rows safely.

Audit details (start time, limit, processed count, errors) are persisted in `orders.backfill_audit` for traceability.
