package com.sivalabs.bookstore.orders.domain;

import com.sivalabs.bookstore.orders.api.model.Customer;
import com.sivalabs.bookstore.orders.api.model.OrderItem;
import com.sivalabs.bookstore.orders.api.model.OrderStatus;
import jakarta.persistence.AttributeOverride;
import jakarta.persistence.AttributeOverrides;
import jakarta.persistence.Column;
import jakarta.persistence.Embedded;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.SequenceGenerator;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Entity
@Table(
        name = "orders",
        schema = "orders",
        indexes = {
            @Index(name = "idx_order_number", columnList = "orderNumber", unique = true),
            @Index(name = "idx_order_status", columnList = "status"),
            @Index(name = "idx_order_created_at", columnList = "created_at")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class OrderEntity extends BaseEntity {

    private static final long serialVersionUID = 1L;

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "order_id_generator")
    @SequenceGenerator(name = "order_id_generator", sequenceName = "order_id_seq", schema = "orders")
    private Long id;

    @Column(nullable = false, unique = true)
    private String orderNumber;

    @Embedded
    @AttributeOverrides(
            value = {
                @AttributeOverride(name = "name", column = @Column(name = "customer_name")),
                @AttributeOverride(name = "email", column = @Column(name = "customer_email")),
                @AttributeOverride(name = "phone", column = @Column(name = "customer_phone"))
            })
    private Customer customer;

    @Column(nullable = false)
    private String deliveryAddress;

    @Embedded
    @AttributeOverrides(
            value = {
                @AttributeOverride(name = "code", column = @Column(name = "product_code")),
                @AttributeOverride(name = "name", column = @Column(name = "product_name")),
                @AttributeOverride(name = "price", column = @Column(name = "product_price")),
                @AttributeOverride(name = "quantity", column = @Column(name = "quantity"))
            })
    private OrderItem orderItem;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private OrderStatus status = OrderStatus.NEW;

    /**
     * Optimistic locking discriminator. A transaction that writes on top of a stale read fails with
     * {@code ObjectOptimisticLockingFailureException} instead of silently overwriting the whole row,
     * so concurrent status changes (for example cancel vs. confirm) can no longer lose each other.
     * Left {@code null} for not-yet-persisted instances so Spring Data still treats them as new.
     */
    @Version
    @Column(name = "version")
    private Long version;
}
