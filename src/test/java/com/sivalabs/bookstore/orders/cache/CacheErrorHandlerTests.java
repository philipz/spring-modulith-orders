package com.sivalabs.bookstore.orders.cache;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Disabled;
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

    @Nested
    @DisplayName("Half-open state machine and failure window (issue #56)")
    class HalfOpenStateMachine {

        // These tests reproduce the three violations found by the as-is model of issue #50
        // (specs/circuit-breaker traces INV_halfOpenFailureReopens, INV_halfOpenFailureRestartsTimer,
        // INV_halfOpenBoundedRequests, INV_closedFailureCounterResetsPeriodically). They were red
        // before the CacheErrorHandler fix landed in this layer of the stack (issue #56).

        @Test
        @DisplayName("Should reopen the circuit and restart the timer when a half-open trial fails")
        void halfOpenFailureReopensCircuitAndRestartsTimer() throws InterruptedException {
            // threshold = 2 failures, recovery timeout = 100 ms
            CacheErrorHandler handler = new CacheErrorHandler(2, 100L);

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
            assertThat(handler.getTotalCircuitOpenings()).isEqualTo(1);

            // Let the recovery timeout elapse so the breaker turns half-open.
            Thread.sleep(150L);
            assertThat(handler.isCircuitOpen()).isFalse();

            // A failing trial request while half-open must reopen the breaker immediately
            // (Azure Circuit Breaker: "If any request fails ... it reverts to the Open state
            // and restarts the time-out timer").
            String result = handler.executeWithFallback(
                    () -> {
                        throw failure();
                    },
                    OPERATION,
                    "key-trial",
                    () -> "fallback");

            assertThat(result).isEqualTo("fallback");
            assertThat(handler.getTotalCircuitOpenings()).isEqualTo(2);
            assertThat(handler.isCircuitOpen()).isTrue();

            // The restarted timer must take effect right away: the next request is rejected
            // without touching the cache even though a full recovery timeout already elapsed.
            AtomicInteger operationCalls = new AtomicInteger();
            String next = handler.executeWithFallback(
                    () -> {
                        operationCalls.incrementAndGet();
                        return "fresh";
                    },
                    OPERATION,
                    "key-next",
                    () -> "fallback");

            assertThat(next).isEqualTo("fallback");
            assertThat(operationCalls.get()).isZero();
        }

        @Test
        @DisplayName("Should admit only one trial request while half-open and only close on trial success")
        void halfOpenAdmitsOnlyOneTrialRequest() throws InterruptedException {
            // threshold = 1 failure, recovery timeout = 100 ms
            CacheErrorHandler handler = new CacheErrorHandler(1, 100L);

            handler.executeWithFallback(
                    () -> {
                        throw failure();
                    },
                    OPERATION,
                    "key-0",
                    () -> "fallback");
            assertThat(handler.isCircuitOpen()).isTrue();
            assertThat(handler.getTotalCircuitOpenings()).isEqualTo(1);

            // Half-open: the recovery timeout elapsed.
            Thread.sleep(150L);
            assertThat(handler.isCircuitOpen()).isFalse();

            // Three requests arrive while the cache is still failing. Only the first may probe
            // the cache; the rest must be treated like the Open state and go straight to fallback.
            AtomicInteger operationCalls = new AtomicInteger();
            for (int i = 0; i < 3; i++) {
                String result = handler.executeWithFallback(
                        () -> {
                            operationCalls.incrementAndGet();
                            throw failure();
                        },
                        OPERATION,
                        "key-trial-" + i,
                        () -> "fallback");
                assertThat(result).isEqualTo("fallback");
            }
            assertThat(operationCalls.get()).isEqualTo(1);
            assertThat(handler.getTotalCircuitOpenings()).isEqualTo(2);
            assertThat(handler.isCircuitOpen()).isTrue();

            // Only after the recovery timeout elapses again may a new trial run,
            // and a successful trial closes the circuit.
            Thread.sleep(150L);
            String recovered = handler.executeWithFallback(() -> "fresh", OPERATION, "key-success", () -> "fallback");

            assertThat(recovered).isEqualTo("fresh");
            assertThat(handler.isCircuitOpen()).isFalse();
        }

        @Test
        @DisplayName("Should restart the closed-state failure counter once the failure window elapses")
        void closedFailureCounterResetsAfterFailureWindow() throws InterruptedException {
            // threshold = 2, long recovery timeout (irrelevant here), failure window = 100 ms
            CacheErrorHandler handler = new CacheErrorHandler(2, 30_000L, 100L);

            handler.handleCacheError(failure(), OPERATION, "key-1");
            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(1);

            // The failure window (100 ms) elapses before the next failure.
            Thread.sleep(150L);

            // The counter must restart with this failure instead of completing the stale window:
            // sporadic failures spread beyond the window never trip the breaker.
            handler.handleCacheError(failure(), OPERATION, "key-2");
            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(1);
            assertThat(handler.isCircuitOpen()).isFalse();
            assertThat(handler.getTotalCircuitOpenings()).isZero();

            // Two failures inside the fresh window still trip the breaker as before.
            handler.handleCacheError(failure(), OPERATION, "key-3");
            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(2);
            assertThat(handler.isCircuitOpen()).isTrue();
            assertThat(handler.getTotalCircuitOpenings()).isEqualTo(1);
        }
    }

    @Nested
    @DisplayName("Closed-state failure window expiry (issue #73)")
    class ClosedFailureWindowExpiry {

        // docs/specs/circuit-breaker.md: "The failure counter for the Closed state is time based.
        // It automatically resets at periodic intervals." The #56 implementation only reset the
        // counter lazily on the next failure (and used a strictly-greater-than window comparison),
        // so reads kept reporting stale counts after the window elapsed, and two failures exactly
        // one window apart were merged into a single trip. These tests drive an injected mutable
        // Clock — window boundaries must never be tested with Thread.sleep.

        private static final Instant START = Instant.parse("2026-01-01T00:00:00Z");

        /** Test-only clock whose instant is advanced explicitly by the test. */
        private static final class MutableClock extends Clock {

            private Instant instant;

            private MutableClock(Instant start) {
                this.instant = start;
            }

            private void advance(Duration delta) {
                instant = instant.plus(delta);
            }

            @Override
            public ZoneId getZone() {
                return ZoneOffset.UTC;
            }

            @Override
            public Clock withZone(ZoneId zone) {
                return this;
            }

            @Override
            public Instant instant() {
                return instant;
            }
        }

        @Test
        @Disabled(
                "Red before the 02-impl fix for issue #73 (stale counter after window expiry); re-enabled in that layer")
        void failureCounterReadsZeroImmediatelyAfterWindowElapsesWithoutNewFailure() {
            // threshold = 2, long recovery timeout (irrelevant here), failure window = 100 ms
            MutableClock clock = new MutableClock(START);
            CacheErrorHandler handler = new CacheErrorHandler(2, 30_000L, 100L, clock);

            handler.handleCacheError(failure(), OPERATION, "key-1");
            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(1);

            // Time moves past the failure window and nothing else fails: the periodic reset must
            // happen on its own, so every reader (getConsecutiveFailureCount, the health
            // indicator and the info contributor) reports 0 from this point on.
            clock.advance(Duration.ofMillis(150));

            assertThat(handler.getConsecutiveFailureCount()).isZero();
            assertThat(handler.isCircuitOpen()).isFalse();
            assertThat(handler.getTotalCircuitOpenings()).isZero();
        }

        @Test
        @Disabled(
                "Red before the 02-impl fix for issue #73 (>= window boundary must restart counting); re-enabled in that layer")
        void twoFailuresExactlyOneWindowApartMustNotBeMergedIntoOneTrip() {
            MutableClock clock = new MutableClock(START);
            CacheErrorHandler handler = new CacheErrorHandler(2, 30_000L, 100L, clock);

            handler.handleCacheError(failure(), OPERATION, "key-1");
            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(1);

            // The second failure lands exactly one window length after the first: the window has
            // elapsed, so counting restarts with this failure instead of completing the stale
            // window (the old strictly-greater-than comparison merged the two and tripped at 2).
            clock.advance(Duration.ofMillis(100));
            handler.handleCacheError(failure(), OPERATION, "key-2");

            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(1);
            assertThat(handler.isCircuitOpen()).isFalse();
            assertThat(handler.getTotalCircuitOpenings()).isZero();
        }

        @Test
        void twoFailuresInsideTheWindowStillOpenTheCircuit() {
            // Control case: the fix must not weaken genuine clustered failures.
            MutableClock clock = new MutableClock(START);
            CacheErrorHandler handler = new CacheErrorHandler(2, 30_000L, 100L, clock);

            handler.handleCacheError(failure(), OPERATION, "key-1");
            clock.advance(Duration.ofMillis(50));
            handler.handleCacheError(failure(), OPERATION, "key-2");

            assertThat(handler.getConsecutiveFailureCount()).isEqualTo(2);
            assertThat(handler.isCircuitOpen()).isTrue();
            assertThat(handler.getTotalCircuitOpenings()).isEqualTo(1);
        }
    }
}
