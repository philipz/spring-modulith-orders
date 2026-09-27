package com.sivalabs.bookstore.orders.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.clearInvocations;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import com.sivalabs.bookstore.orders.InvalidOrderException;
import com.sivalabs.bookstore.orders.api.events.OrderCreatedEvent;
import com.sivalabs.bookstore.orders.api.model.Customer;
import com.sivalabs.bookstore.orders.api.model.OrderItem;
import com.sivalabs.bookstore.orders.api.model.OrderStatus;
import java.math.BigDecimal;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;

@ExtendWith(MockitoExtension.class)
@DisplayName("OrderService Unit Tests")
class OrderServiceUnitTests {

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private ApplicationEventPublisher eventPublisher;

    @Mock
    private OrderCachePort orderCachePort;

    private OrderService orderService;

    @BeforeEach
    void setUp() {
        orderService = new OrderService(orderRepository, eventPublisher);
    }

    @Nested
    @DisplayName("Create Order Tests")
    class CreateOrderTests {

        @Test
        @DisplayName("Should create order successfully with valid entity")
        void shouldCreateOrderSuccessfullyWithValidEntity() {
            // Given
            OrderEntity orderEntity = createValidOrderEntity();
            OrderEntity savedOrder = createSavedOrderEntity();

            given(orderRepository.save(any(OrderEntity.class))).willReturn(savedOrder);

            // When
            OrderEntity result = orderService.createOrder(orderEntity);

            // Then
            assertThat(result).isNotNull();
            assertThat(result.getOrderNumber()).isEqualTo(savedOrder.getOrderNumber());

            ArgumentCaptor<OrderEntity> orderCaptor = ArgumentCaptor.forClass(OrderEntity.class);
            verify(orderRepository).save(orderCaptor.capture());

            OrderEntity capturedOrder = orderCaptor.getValue();
            assertThat(capturedOrder.getCustomer().email())
                    .isEqualTo(orderEntity.getCustomer().email());
            assertThat(capturedOrder.getStatus()).isEqualTo(OrderStatus.NEW);
            assertThat(capturedOrder.getDeliveryAddress()).isEqualTo(orderEntity.getDeliveryAddress());
        }

        @Test
        @DisplayName("Should publish event when order created")
        void shouldPublishEventWhenOrderCreated() {
            // Given
            OrderEntity orderEntity = createValidOrderEntity();
            OrderEntity savedOrder = createSavedOrderEntity();

            given(orderRepository.save(any(OrderEntity.class))).willReturn(savedOrder);

            // When
            orderService.createOrder(orderEntity);

            // Then
            verify(eventPublisher).publishEvent(any(com.sivalabs.bookstore.orders.api.events.OrderCreatedEvent.class));
        }

        @Test
        @DisplayName("Should publish OrderCreatedEvent with expected payload")
        void shouldPublishOrderCreatedEventWithExpectedPayload() {
            // Given
            OrderEntity orderEntity = createValidOrderEntity();
            OrderEntity savedOrder = createSavedOrderEntity("ORD-123456", "PROD-001", 3);

            given(orderRepository.save(any(OrderEntity.class))).willReturn(savedOrder);

            // When
            orderService.createOrder(orderEntity);

            // Then
            ArgumentCaptor<OrderCreatedEvent> eventCaptor = ArgumentCaptor.forClass(OrderCreatedEvent.class);
            verify(eventPublisher).publishEvent(eventCaptor.capture());

            OrderCreatedEvent publishedEvent = eventCaptor.getValue();
            assertThat(publishedEvent.orderNumber()).isEqualTo(savedOrder.getOrderNumber());
            assertThat(publishedEvent.productCode())
                    .isEqualTo(savedOrder.getOrderItem().code());
            assertThat(publishedEvent.quantity())
                    .isEqualTo(savedOrder.getOrderItem().quantity());
            assertThat(publishedEvent.customer()).isEqualTo(savedOrder.getCustomer());
        }

        @Test
        @DisplayName("Should generate unique order number")
        void shouldGenerateUniqueOrderNumber() {
            // Given
            OrderEntity orderEntity = createValidOrderEntity();
            OrderEntity savedOrder = createSavedOrderEntity();

            given(orderRepository.save(any(OrderEntity.class))).willReturn(savedOrder);

            // When
            OrderEntity result = orderService.createOrder(orderEntity);

            // Then
            assertThat(result.getOrderNumber()).isNotBlank();
            assertThat(result.getOrderNumber()).hasSize(36); // UUID length
        }
    }

    @Nested
    @DisplayName("Find Order Tests")
    class FindOrderTests {

        @Test
        @DisplayName("Should find order by order number")
        void shouldFindOrderByOrderNumber() {
            // Given
            String orderNumber = "test-order-123";
            OrderEntity existingOrder = createOrderEntityWithOrderNumber(orderNumber);

            given(orderRepository.findByOrderNumber(orderNumber)).willReturn(Optional.of(existingOrder));

            // When
            Optional<OrderEntity> result = orderService.findOrder(orderNumber);

            // Then
            assertThat(result).isPresent();
            assertThat(result.get()).isEqualTo(existingOrder);
            verify(orderRepository).findByOrderNumber(orderNumber);
        }

        @Test
        @DisplayName("Should return empty when order not found")
        void shouldReturnEmptyWhenOrderNotFound() {
            // Given
            String orderNumber = "non-existent-order";

            given(orderRepository.findByOrderNumber(orderNumber)).willReturn(Optional.empty());

            // When
            Optional<OrderEntity> result = orderService.findOrder(orderNumber);

            // Then
            assertThat(result).isEmpty();
            verify(orderRepository).findByOrderNumber(orderNumber);
        }
    }

    @Nested
    @DisplayName("Input Validation Tests")
    class InputValidationTests {

        @Test
        @DisplayName("Should throw exception for null entity")
        void shouldThrowExceptionForNullEntity() {
            // When & Then
            assertThatThrownBy(() -> orderService.createOrder(null)).isInstanceOf(NullPointerException.class);

            verify(orderRepository, never()).save(any(OrderEntity.class));
        }
    }

    @Nested
    @DisplayName("Order Status Transition Rules (Issue #57)")
    class StatusTransitionRuleTests {

        /**
         * Issue #51 業務規則 R1–R5 的獨立重寫（測試端定義「正確」）： NEW → PENDING → CONFIRMED →
         * IN_PROCESS → SHIPPED → DELIVERED 逐步前進； NEW、PENDING → CANCELLED； NEW、PENDING、CONFIRMED、IN_PROCESS →
         * ERROR； DELIVERED、CANCELLED、ERROR 為終態；同值寫入不允許。
         */
        private boolean ruleAllowsTransition(OrderStatus from, OrderStatus to) {
            if (from == to) {
                return false;
            }
            return switch (to) {
                case PENDING -> from == OrderStatus.NEW;
                case CONFIRMED -> from == OrderStatus.PENDING;
                case IN_PROCESS -> from == OrderStatus.CONFIRMED;
                case SHIPPED -> from == OrderStatus.IN_PROCESS;
                case DELIVERED -> from == OrderStatus.SHIPPED;
                case CANCELLED -> from == OrderStatus.NEW || from == OrderStatus.PENDING;
                case ERROR ->
                    from == OrderStatus.NEW
                            || from == OrderStatus.PENDING
                            || from == OrderStatus.CONFIRMED
                            || from == OrderStatus.IN_PROCESS;
                case NEW -> false;
            };
        }

        private OrderEntity orderWithStatus(String orderNumber, OrderStatus status) {
            Customer customer = new Customer("John Doe", "john@example.com", "+1234567890");
            OrderItem orderItem = new OrderItem("PROD-001", "Test Product", BigDecimal.valueOf(99.99), 1);
            return OrderEntity.builder()
                    .id(1L)
                    .orderNumber(orderNumber)
                    .customer(customer)
                    .deliveryAddress("123 Test Street")
                    .orderItem(orderItem)
                    .status(status)
                    .build();
        }

        @Test
        @DisplayName("Allowed transitions update the status and save the order")
        void allowedTransitionsUpdateAndSave() {
            OrderStatus[][] allowed = {
                {OrderStatus.NEW, OrderStatus.PENDING},
                {OrderStatus.PENDING, OrderStatus.CONFIRMED},
                {OrderStatus.CONFIRMED, OrderStatus.IN_PROCESS},
                {OrderStatus.IN_PROCESS, OrderStatus.SHIPPED},
                {OrderStatus.SHIPPED, OrderStatus.DELIVERED},
                {OrderStatus.NEW, OrderStatus.CANCELLED},
                {OrderStatus.PENDING, OrderStatus.CANCELLED},
                {OrderStatus.NEW, OrderStatus.ERROR},
                {OrderStatus.PENDING, OrderStatus.ERROR},
                {OrderStatus.CONFIRMED, OrderStatus.ERROR},
                {OrderStatus.IN_PROCESS, OrderStatus.ERROR},
            };

            for (OrderStatus[] step : allowed) {
                String orderNumber = "ord-allowed-" + step[0] + "-" + step[1];
                OrderEntity order = orderWithStatus(orderNumber, step[0]);
                clearInvocations(orderRepository);
                given(orderRepository.findByOrderNumber(orderNumber)).willReturn(Optional.of(order));
                given(orderRepository.save(any(OrderEntity.class))).willAnswer(invocation -> invocation.getArgument(0));

                OrderEntity result = orderService.updateOrderStatus(orderNumber, step[1]);

                assertThat(result.getStatus()).isEqualTo(step[1]);
                verify(orderRepository).save(any(OrderEntity.class));
            }
        }

        @Test
        @Disabled("Red until issue #57 impl lands: updateOrderStatus currently performs every transition")
        @DisplayName("Disallowed transitions throw IllegalStateException and never save")
        void disallowedTransitionsThrowAndNeverSave() {
            for (OrderStatus from : OrderStatus.values()) {
                for (OrderStatus to : OrderStatus.values()) {
                    if (ruleAllowsTransition(from, to)) {
                        continue;
                    }
                    String orderNumber = "ord-disallowed-" + from + "-" + to;
                    OrderEntity order = orderWithStatus(orderNumber, from);
                    clearInvocations(orderRepository);
                    given(orderRepository.findByOrderNumber(orderNumber)).willReturn(Optional.of(order));

                    assertThatThrownBy(() -> orderService.updateOrderStatus(orderNumber, to))
                            .isInstanceOf(IllegalStateException.class)
                            .hasMessageContaining(orderNumber);
                    assertThat(order.getStatus()).isEqualTo(from);
                    verify(orderRepository, never()).save(any(OrderEntity.class));
                }
            }
        }

        @Test
        @Disabled("Red until issue #57 impl lands: terminal states currently accept transitions")
        @DisplayName("Terminal states DELIVERED, CANCELLED, ERROR reject every transition")
        void terminalStatesRejectEveryTransition() {
            for (OrderStatus terminal :
                    new OrderStatus[] {OrderStatus.DELIVERED, OrderStatus.CANCELLED, OrderStatus.ERROR}) {
                for (OrderStatus to : OrderStatus.values()) {
                    String orderNumber = "ord-terminal-" + terminal + "-" + to;
                    OrderEntity order = orderWithStatus(orderNumber, terminal);
                    clearInvocations(orderRepository);
                    given(orderRepository.findByOrderNumber(orderNumber)).willReturn(Optional.of(order));

                    assertThatThrownBy(() -> orderService.updateOrderStatus(orderNumber, to))
                            .isInstanceOf(IllegalStateException.class)
                            .hasMessageContaining(orderNumber);
                    verify(orderRepository, never()).save(any(OrderEntity.class));
                }
            }
        }

        @Test
        @Disabled("Red until issue #57 impl lands: same-value writes currently pass through")
        @DisplayName("Same-value writes such as PENDING to PENDING are rejected")
        void sameValueWritesAreRejected() {
            for (OrderStatus status : OrderStatus.values()) {
                String orderNumber = "ord-same-value-" + status;
                OrderEntity order = orderWithStatus(orderNumber, status);
                clearInvocations(orderRepository);
                given(orderRepository.findByOrderNumber(orderNumber)).willReturn(Optional.of(order));

                assertThatThrownBy(() -> orderService.updateOrderStatus(orderNumber, status))
                        .isInstanceOf(IllegalStateException.class)
                        .hasMessageContaining(orderNumber);
                verify(orderRepository, never()).save(any(OrderEntity.class));
            }
        }

        @Test
        @Disabled("Red until issue #57 impl lands: createOrder currently accepts any initial status")
        @DisplayName("createOrder rejects every initial status other than NEW and never saves")
        void createOrderRejectsNonNewInitialStatus() {
            for (OrderStatus status : OrderStatus.values()) {
                if (status == OrderStatus.NEW) {
                    continue;
                }
                OrderEntity orderEntity = orderWithStatus("ord-initial-" + status, status);
                clearInvocations(orderRepository);

                assertThatThrownBy(() -> orderService.createOrder(orderEntity))
                        .isInstanceOf(InvalidOrderException.class);
            }
            verify(orderRepository, never()).save(any(OrderEntity.class));
        }

        @Test
        @DisplayName("createOrder keeps defaulting a missing status to NEW")
        void createOrderDefaultsMissingStatusToNew() {
            OrderEntity orderEntity = orderWithStatus("ord-missing-status", null);
            given(orderRepository.save(any(OrderEntity.class))).willAnswer(invocation -> invocation.getArgument(0));

            OrderEntity result = orderService.createOrder(orderEntity);

            assertThat(result.getStatus()).isEqualTo(OrderStatus.NEW);
            verify(orderRepository).save(any(OrderEntity.class));
        }
    }

    // Helper methods
    private OrderEntity createValidOrderEntity() {
        Customer customer = new Customer("John Doe", "john@example.com", "+1234567890");
        OrderItem orderItem = new OrderItem("PROD-001", "Test Product", BigDecimal.valueOf(99.99), 1);
        return OrderEntity.builder()
                .customer(customer)
                .deliveryAddress("123 Test Street")
                .orderItem(orderItem)
                .status(OrderStatus.NEW)
                .build();
    }

    private OrderEntity createSavedOrderEntity() {
        return createSavedOrderEntity(java.util.UUID.randomUUID().toString(), "PROD-001", 1);
    }

    private OrderEntity createSavedOrderEntity(String orderNumber, String productCode, int quantity) {
        Customer customer = new Customer("John Doe", "john@example.com", "+1234567890");
        OrderItem orderItem = new OrderItem(productCode, "Test Product", BigDecimal.valueOf(99.99), quantity);
        return OrderEntity.builder()
                .id(1L)
                .orderNumber(orderNumber)
                .customer(customer)
                .deliveryAddress("123 Test Street")
                .orderItem(orderItem)
                .status(OrderStatus.NEW)
                .build();
    }

    private OrderEntity createOrderEntityWithOrderNumber(String orderNumber) {
        Customer customer = new Customer("John Doe", "john@example.com", "+1234567890");
        OrderItem orderItem = new OrderItem("PROD-001", "Test Product", BigDecimal.valueOf(99.99), 1);

        return OrderEntity.builder()
                .id(1L)
                .orderNumber(orderNumber)
                .customer(customer)
                .deliveryAddress("123 Test Street")
                .orderItem(orderItem)
                .status(OrderStatus.NEW)
                .build();
    }
}
