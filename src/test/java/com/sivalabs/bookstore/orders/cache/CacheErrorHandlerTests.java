package com.sivalabs.bookstore.orders.cache;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

@DisplayName("CacheErrorHandler Unit Tests")
class CacheErrorHandlerTests {

    private static final String OPERATION = "orders:cache";

    private int circuitOpeningThreshold(int threshold) {
        // One call opens the circuit; this helper returns how many failures are needed before open.
        return threshold - 1;
    }

    private <T> RuntimeException failure() {
        return new RuntimeException("cache unavailable");
    }

    @Nested
    @DisplayName("Successful operation")
    class SuccessfulOperation {

        @Test
        @DisplayName("Should return operation result and not count a failure")
        void shouldReturnResultAndNotCountFailure() {
            CacheErrorHandler handler = new CacheErrorHandler();
            AtomicInteger counter = new AtomicInteger();

            Object result = handler.executeWithFallback(
                    () -> {
                        counter.incrementAndGet();
                        return "value";
                    },
                    OPERATION,
                    "key-1",
                    () -> null);

            assertThat(result).isEqualTo("value");
            assertThat(handler.getConsecutiveFailureCount()).isZero();
            assertThat(handler.getTrackedErrorCount()).isZero();
            assertThat(handler.isCircuitOpen()).isFalse();
        }

        @Test
        @DisplayName("Should reset consecutive failures after a prior failure")
        void shouldResetConsecutiveFailuresAfterSuccess() {
            CacheErrorHandler handler = new CacheErrorHandler();

            handler.handleCacheError(failure(), OPERATION, "key-1");

            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(1);

            Object result = handler.executeWithFallback(() -> "ok", OPERATION, "key-1", () -> null);

            assertThat(result).isEqualTo("ok");
            assertThat(handler.getConsecutiveFailureCount()).isZero();
        }
    }

    @Nested
    @DisplayName("Circuit opening behavior")
    class CircuitOpening {

        @Test
        @DisplayName("Should execute the operation below the failure threshold")
        void shouldExecuteOperationBelowThreshold() {
            CacheErrorHandler handler = new CacheErrorHandler();
            AtomicInteger counter = new AtomicInteger();

            handler.executeWithFallback(
                    () -> {
                        counter.incrementAndGet();
                        throw failure();
                    },
                    OPERATION,
                    "key-1",
                    () -> "fallback");

            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(1);
            assertThat(handler.isCircuitOpen()).isFalse();
            assertThat(handler.getTotalCircuitOpenings()).isZero();
        }

        @Test
        @DisplayName("Should return fallback result when operation fails but circuit is below threshold")
        void shouldReturnFallbackWhenOperationFailsBelowThreshold() {
            CacheErrorHandler handler = new CacheErrorHandler();

            String result = handler.executeWithFallback(
                    () -> {
                        throw failure();
                    },
                    OPERATION,
                    "key-1",
                    () -> "fallback");

            assertThat(result).isEqualTo("fallback");
            assertThat(handler.getFallbackRecommendationCount()).isEqualTo(1);
        }

        @Test
        @DisplayName("Should open the circuit after consecutive failures reach the threshold")
        void shouldOpenCircuitAfterThresholdReached() {
            // Default no-arg constructor: threshold = 5
            CacheErrorHandler handler = new CacheErrorHandler();

            // 4 failures keep it below the threshold
            for (int i = 0; i < circuitOpeningThreshold(5); i++) {
                handler.executeWithFallback(
                        () -> {
                            throw failure();
                        },
                        OPERATION,
                        "key-" + i,
                        () -> "fallback");
            }

            assertThat(handler.isCircuitOpen()).isFalse();
            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(4);
            assertThat(handler.getTotalCircuitOpenings()).isZero();

            // 5th consecutive failure opens the circuit
            handler.executeWithFallback(
                    () -> {
                        throw failure();
                    },
                    OPERATION,
                    "key-4",
                    () -> "fallback");

            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(5);
            assertThat(handler.isCircuitOpen()).isTrue();
            assertThat(handler.getTotalCircuitOpenings()).isEqualTo(1);
        }

        @Test
        @DisplayName("Should use fallback and not execute the operation while the circuit is open")
        void shouldFallbackWithoutExecutingOperationWhileOpen() {
            CacheErrorHandler handler = new CacheErrorHandler();

            // Open the circuit with the default threshold = 5
            for (int i = 0; i < 5; i++) {
                handler.executeWithFallback(
                        () -> {
                            throw failure();
                        },
                        OPERATION,
                        "key-" + i,
                        () -> "fallback");
            }
            assertThat(handler.isCircuitOpen()).isTrue();

            AtomicInteger operationCalls = new AtomicInteger();
            int callsBefore = operationCalls.get();
            int fallbacksBefore = handler.getFallbackRecommendationCount();

            String result = handler.executeWithFallback(
                    () -> {
                        operationCalls.incrementAndGet();
                        return "fresh";
                    },
                    OPERATION,
                    "key-9",
                    () -> "fallback");

            assertThat(result).isEqualTo("fallback");
            assertThat(operationCalls.get()).isEqualTo(callsBefore);
            assertThat(handler.getFallbackRecommendationCount()).isEqualTo(fallbacksBefore + 1);
        }
    }

    @Nested
    @DisplayName("Recovery after timeout")
    class Recovery {

        @Test
        @DisplayName("Should retry the operation after the recovery timeout has elapsed")
        void shouldRetryAfterRecoveryTimeout() throws InterruptedException {
            // Use a short recovery timeout (50 ms) so the timeout elapses quickly in the test.
            CacheErrorHandler handler = new CacheErrorHandler(2, 50L);

            // Fail twice to open the circuit
            for (int i = 0; i < 2; i++) {
                handler.executeWithFallback(
                        () -> {
                            throw failure();
                        },
                        OPERATION,
                        "key-" + i,
                        () -> "fallback");
            }
            assertThat(handler.isCircuitOpen()).isTrue();

            // Wait past the recovery timeout
            Thread.sleep(150L);

            assertThat(handler.isCircuitOpen()).isFalse();

            AtomicInteger operationCalls = new AtomicInteger();
            String result = handler.executeWithFallback(
                    () -> {
                        operationCalls.incrementAndGet();
                        return "recovered";
                    },
                    OPERATION,
                    "key-recovered",
                    () -> "fallback");

            assertThat(result).isEqualTo("recovered");
            assertThat(operationCalls.get()).isEqualTo(1);
        }

        @Test
        @DisplayName("Should fall back directly when circuit open and recovery timeout not yet elapsed")
        void shouldFallbackWhenTimeoutNotYetElapsed() {
            // Long timeout (30s default via no-arg) so the circuit stays open during the test.
            CacheErrorHandler handler = new CacheErrorHandler();

            for (int i = 0; i < 5; i++) {
                handler.executeWithFallback(
                        () -> {
                            throw failure();
                        },
                        OPERATION,
                        "key-" + i,
                        () -> "fallback");
            }
            assertThat(handler.isCircuitOpen()).isTrue();

            AtomicReference<String> result = new AtomicReference<>();
            AtomicInteger operationCalls = new AtomicInteger();
            result.set(handler.executeWithFallback(
                    () -> {
                        operationCalls.incrementAndGet();
                        return "fresh";
                    },
                    OPERATION,
                    "key-99",
                    () -> "fallback"));

            assertThat(result.get()).isEqualTo("fallback");
            assertThat(operationCalls.get()).isZero();
        }
    }

    @Nested
    @DisplayName("Failure counting and key tracking")
    class FailureTracking {

        @Test
        @DisplayName("Should track error counts and last error times per operation and key")
        void shouldTrackErrorsPerOperation() {
            CacheErrorHandler handler = new CacheErrorHandler();

            handler.handleCacheError(failure(), OPERATION, "key-1");
            handler.handleCacheError(failure(), OPERATION, "key-2");
            handler.handleCacheError(failure(), "other-cache", "key-3");

            assertThat(handler.getTrackedErrorCount()).isEqualTo(3);
            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(3);

            String stats = handler.getCacheErrorStats();
            assertThat(stats).contains(OPERATION);
            assertThat(stats).contains("other-cache");
            assertThat(stats).contains("Last Error Times:");
        }

        @Test
        @DisplayName("Should reset tracked error state after resetErrorState")
        void shouldResetErrorState() {
            CacheErrorHandler handler = new CacheErrorHandler();

            handler.handleCacheError(failure(), OPERATION, "key-1");
            handler.executeWithFallback(
                    () -> {
                        throw failure();
                    },
                    OPERATION,
                    "key-1",
                    () -> null);

            assertThat(handler.getTrackedErrorCount()).isEqualTo(2);

            handler.resetErrorState();

            assertThat(handler.getConsecutiveFailureCount()).isZero();
            assertThat(handler.getTrackedErrorCount()).isZero();
            assertThat(handler.getFallbackRecommendationCount()).isZero();
            assertThat(handler.isCircuitOpen()).isFalse();
        }

        @Test
        @DisplayName("Should clear tracked errors for an operation on success")
        void shouldClearTrackedErrorsOnSuccess() {
            CacheErrorHandler handler = new CacheErrorHandler();

            handler.handleCacheError(failure(), OPERATION, "key-1");

            assertThat(handler.getTrackedErrorCount()).isEqualTo(1);

            handler.recordSuccess(OPERATION);

            assertThat(handler.getTrackedErrorCount()).isZero();
            // Consecutive failures reset by recordSuccess
            assertThat(handler.getConsecutiveFailureCount()).isZero();
        }
    }

    @Nested
    @DisplayName("Void operations and health checks")
    class VoidAndHealth {

        @Test
        @DisplayName("Should run a void operation and report success when it does not throw")
        void shouldRunVoidOperationOnSuccess() {
            CacheErrorHandler handler = new CacheErrorHandler();
            AtomicInteger calls = new AtomicInteger();

            boolean success = handler.executeVoidOperation(calls::incrementAndGet, OPERATION, "key-1");

            assertThat(success).isTrue();
            assertThat(calls.get()).isEqualTo(1);
            assertThat(handler.getConsecutiveFailureCount()).isZero();
        }

        @Test
        @DisplayName("Should return fallback recommendation when a void operation fails")
        void shouldReturnFallbackWhenVoidOperationFails() {
            CacheErrorHandler handler = new CacheErrorHandler();

            boolean success = handler.executeVoidOperation(
                    () -> {
                        throw failure();
                    },
                    OPERATION,
                    "key-1");

            assertThat(success).isFalse();
            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(1);
            assertThat(handler.getFallbackRecommendationCount()).isEqualTo(1);
        }

        @Test
        @DisplayName("Should close the circuit when the health check passes")
        void shouldCloseCircuitWhenHealthCheckPasses() {
            CacheErrorHandler handler = new CacheErrorHandler();

            for (int i = 0; i < 5; i++) {
                handler.executeWithFallback(
                        () -> {
                            throw failure();
                        },
                        OPERATION,
                        "key-" + i,
                        () -> "fallback");
            }
            assertThat(handler.isCircuitOpen()).isTrue();

            boolean healthy = handler.checkCacheHealth(() -> true);

            assertThat(healthy).isTrue();
            assertThat(handler.isCircuitOpen()).isFalse();
            assertThat(handler.getConsecutiveFailureCount()).isZero();
        }

        @Test
        @DisplayName("Should keep the circuit open when the health check fails")
        void shouldKeepCircuitOpenWhenHealthCheckFails() {
            CacheErrorHandler handler = new CacheErrorHandler();

            for (int i = 0; i < 5; i++) {
                handler.executeWithFallback(
                        () -> {
                            throw failure();
                        },
                        OPERATION,
                        "key-" + i,
                        () -> "fallback");
            }
            assertThat(handler.isCircuitOpen()).isTrue();

            boolean healthy = handler.checkCacheHealth(() -> false);

            assertThat(healthy).isFalse();
            assertThat(handler.isCircuitOpen()).isTrue();
        }
    }
}
