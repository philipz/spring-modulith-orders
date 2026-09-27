package com.sivalabs.bookstore.orders.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import com.sivalabs.bookstore.orders.api.model.Customer;
import com.sivalabs.bookstore.orders.api.model.OrderItem;
import com.sivalabs.bookstore.orders.api.model.OrderStatus;
import com.sivalabs.bookstore.orders.support.DockerAvailability;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.TestPropertySource;
import org.springframework.transaction.support.TransactionTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Reproduces the concurrent lost-update defect reported in issue #58: two transactions that both
 * start from the same snapshot of an order must not silently overwrite each other. The later commit
 * has to fail with an optimistic locking error instead of resurrecting a stale status.
 *
 * <p>Disabled on the 01-test layer of the stack because the {@code @Version} mapping and the
 * Liquibase change set that back these assertions only land on the 02-impl layer; the layer above
 * re-enables the class together with the fix.
 */
@SpringBootTest(webEnvironment = WebEnvironment.NONE)
@Testcontainers(disabledWithoutDocker = true)
@TestPropertySource(
        properties = {
            "bookstore.cache.enabled=false",
            "app.amqp.new-orders.bind=false",
            "spring.rabbitmq.listener.direct.auto-startup=false",
            "spring.rabbitmq.listener.simple.auto-startup=false",
            "grpc.client.orders.enabled=false"
        })
@DisplayName("Order Concurrent Update Integration Tests")
@Disabled("Enabled by the 02-impl layer of issue #58 together with the optimistic locking fix")
class OrderConcurrentUpdateIntegrationTests {

    private static final long TIMEOUT_SECONDS = 20L;

    static {
        assumeTrue(DockerAvailability.isDockerAvailable(), "Docker is required for Integration Tests");
    }

    @Container
    static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:17-alpine")
            .withDatabaseName("ordersdb")
            .withUsername("orders")
            .withPassword("orders")
            .withInitScript("db/test-init.sql");

    @DynamicPropertySource
    static void registerProperties(DynamicPropertyRegistry registry) {
        assumeTrue(DockerAvailability.isDockerAvailable(), "Docker is required for Integration Tests");
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.datasource.driver-class-name", () -> "org.postgresql.Driver");
        registry.add("spring.jpa.hibernate.ddl-auto", () -> "none");
        registry.add("spring.liquibase.enabled", () -> true);
        registry.add("grpc.server.port", () -> -1);
    }

    @Autowired
    private OrderRepository orderRepository;

    @Autowired
    private TransactionTemplate transactionTemplate;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @MockBean
    private ConnectionFactory connectionFactory;

    private ExecutorService executor;

    @BeforeEach
    void setUp() {
        orderRepository.deleteAll();
        executor = Executors.newSingleThreadExecutor();
    }

    @AfterEach
    void tearDown() {
        executor.shutdownNow();
    }

    @Test
    @DisplayName("Stale transaction must fail instead of overwriting a freshly committed status")
    void staleTransactionMustNotOverwriteCommittedStatus() {
        String orderNumber = seedPendingOrder();

        CountDownLatch staleReadDone = new CountDownLatch(1);
        CountDownLatch freshCommitDone = new CountDownLatch(1);

        // Transaction A: reads the order while it is still PENDING, then tries to cancel it *after*
        // transaction B has already moved it forward.
        Future<Throwable> transactionA = executor.submit(() -> captureFailure(() -> {
            try {
                transactionTemplate.executeWithoutResult(status -> {
                    OrderEntity staleView = requireOrder(orderNumber);
                    assertThat(staleView.getStatus()).isEqualTo(OrderStatus.PENDING);
                    staleReadDone.countDown();
                    await(freshCommitDone, "transaction B to commit");

                    staleView.setStatus(OrderStatus.CANCELLED);
                    orderRepository.saveAndFlush(staleView);
                });
            } finally {
                staleReadDone.countDown();
            }
        }));

        await(staleReadDone, "transaction A to read the order");

        // Transaction B: confirms the order and commits while transaction A is still open.
        transactionTemplate.executeWithoutResult(status -> {
            OrderEntity freshView = requireOrder(orderNumber);
            freshView.setStatus(OrderStatus.CONFIRMED);
            orderRepository.saveAndFlush(freshView);
        });
        freshCommitDone.countDown();

        Throwable transactionAOutcome = resolve(transactionA);

        assertThat(transactionAOutcome)
                .as("transaction A wrote on top of a stale read instead of failing")
                .isInstanceOf(ObjectOptimisticLockingFailureException.class);
        assertThat(currentStatus(orderNumber))
                .as("the committed CONFIRMED status was overwritten by a stale CANCELLED write")
                .isEqualTo(OrderStatus.CONFIRMED);
    }

    @Test
    @DisplayName("Migration adds a version column that defaults to zero and increments on update")
    void versionColumnDefaultsToZeroAndIncrementsOnUpdate() {
        String orderNumber = "ISSUE58-" + UUID.randomUUID().toString().substring(0, 8);

        // Insert without mentioning the version column: mirrors rows that already existed before
        // the migration, which must default to 0.
        jdbcTemplate.update(
                """
                insert into orders.orders (order_number, customer_name, customer_email, customer_phone,
                        delivery_address, product_code, product_name, product_price, quantity, status, created_at)
                values (?, 'Legacy Row', 'legacy@example.com', '+15550001111', '1 Legacy Way',
                        'P-LEGACY', 'Legacy Product', '19.99', 1, 'PENDING', ?)
                """,
                orderNumber,
                LocalDateTime.now());

        assertThat(versionOf(orderNumber))
                .as("pre-existing rows must be migrated with version 0")
                .isZero();

        transactionTemplate.executeWithoutResult(status -> {
            OrderEntity order = requireOrder(orderNumber);
            order.setStatus(OrderStatus.CONFIRMED);
            orderRepository.saveAndFlush(order);
        });

        assertThat(versionOf(orderNumber))
                .as("a committed update must bump the optimistic locking version")
                .isEqualTo(1L);
        assertThat(currentStatus(orderNumber)).isEqualTo(OrderStatus.CONFIRMED);
    }

    private String seedPendingOrder() {
        String orderNumber = "ISSUE58-" + UUID.randomUUID().toString().substring(0, 8);
        OrderEntity order = OrderEntity.builder()
                .orderNumber(orderNumber)
                .customer(new Customer("Concurrency Tester", "concurrency@example.com", "+1234567890"))
                .deliveryAddress("221B Baker Street")
                .orderItem(new OrderItem("P-CONC", "Concurrency Product", BigDecimal.valueOf(19.99), 1))
                .status(OrderStatus.PENDING)
                .build();
        transactionTemplate.executeWithoutResult(status -> orderRepository.saveAndFlush(order));
        return orderNumber;
    }

    private OrderEntity requireOrder(String orderNumber) {
        return orderRepository
                .findByOrderNumber(orderNumber)
                .orElseThrow(() -> new IllegalStateException("Order not found: " + orderNumber));
    }

    private OrderStatus currentStatus(String orderNumber) {
        String status = jdbcTemplate.queryForObject(
                "select status from orders.orders where order_number = ?", String.class, orderNumber);
        return OrderStatus.valueOf(status);
    }

    private Long versionOf(String orderNumber) {
        return jdbcTemplate.queryForObject(
                "select version from orders.orders where order_number = ?", Long.class, orderNumber);
    }

    private static Throwable captureFailure(Runnable action) {
        try {
            action.run();
            return null;
        } catch (Throwable ex) {
            return ex;
        }
    }

    private static void await(CountDownLatch latch, String description) {
        try {
            if (!latch.await(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                throw new IllegalStateException("Timed out waiting for " + description);
            }
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while waiting for " + description, ex);
        }
    }

    private static Throwable resolve(Future<Throwable> future) {
        try {
            return future.get(TIMEOUT_SECONDS, TimeUnit.SECONDS);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while waiting for transaction A", ex);
        } catch (ExecutionException | TimeoutException ex) {
            throw new IllegalStateException("Transaction A did not finish", ex);
        }
    }
}
