package com.sivalabs.bookstore.orders.infrastructure.catalog;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;

import com.sivalabs.bookstore.orders.InvalidOrderException;
import io.github.resilience4j.springboot.circuitbreaker.autoconfigure.CircuitBreakerAutoConfiguration;
import io.github.resilience4j.springboot.retry.autoconfigure.RetryAutoConfiguration;
import java.math.BigDecimal;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.EnableAspectJAutoProxy;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class HttpProductCatalogClientTests {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withConfiguration(
                    AutoConfigurations.of(CircuitBreakerAutoConfiguration.class, RetryAutoConfiguration.class))
            .withUserConfiguration(AspectJConfig.class)
            // Mirror the catalogApi resilience settings from application.properties
            .withPropertyValues(
                    "resilience4j.circuitbreaker.instances.catalogApi.ignore-exceptions=com.sivalabs.bookstore.orders.InvalidOrderException",
                    "resilience4j.retry.instances.catalogApi.max-attempts=3",
                    "resilience4j.retry.instances.catalogApi.wait-duration=10ms",
                    "resilience4j.retry.instances.catalogApi.retry-exceptions=org.springframework.web.client.HttpServerErrorException,java.io.IOException")
            .withBean(HttpProductCatalogClient.class);

    @Test
    @DisplayName("Should raise CatalogServiceException when the catalog service is unreachable")
    void shouldRaiseCatalogServiceExceptionWhenCatalogUnreachable() {
        contextRunner
                .withBean(
                        RestClient.class,
                        () -> RestClient.builder().baseUrl("http://localhost:1").build())
                .run(context -> assertThatThrownBy(() -> context.getBean(HttpProductCatalogClient.class)
                                .validate("P100", new BigDecimal("29.99")))
                        .isInstanceOf(CatalogServiceException.class));
    }

    @Test
    @DisplayName("Should keep InvalidOrderException when the product does not exist")
    void shouldKeepInvalidOrderExceptionWhenProductNotFound() {
        RestClient.Builder builder = RestClient.builder().baseUrl("http://catalog");
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo("http://catalog/api/products/UNKNOWN")).andRespond(withStatus(HttpStatus.NOT_FOUND));

        contextRunner.withBean(RestClient.class, builder::build).run(context -> assertThatThrownBy(() ->
                        context.getBean(HttpProductCatalogClient.class).validate("UNKNOWN", new BigDecimal("29.99")))
                .isInstanceOf(InvalidOrderException.class));
    }

    @EnableAspectJAutoProxy(proxyTargetClass = true)
    static class AspectJConfig {}
}
