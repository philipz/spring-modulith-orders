package com.sivalabs.bookstore.orders.cache;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class CacheErrorHandler {

    private static final Logger logger = LoggerFactory.getLogger(CacheErrorHandler.class);

    private final int failureThreshold;
    private final Duration circuitOpenDuration;
    private final Duration failureWindow;
    private final Clock clock;

    private final AtomicInteger consecutiveFailures = new AtomicInteger(0);
    private volatile LocalDateTime firstFailureAt = null;
    private volatile LocalDateTime circuitOpenedAt = null;
    private volatile boolean circuitOpen = false;
    private final AtomicBoolean halfOpenTrialActive = new AtomicBoolean(false);
    private final AtomicInteger totalCircuitOpenings = new AtomicInteger(0);
    private final AtomicInteger fallbackRecommendations = new AtomicInteger(0);

    private final ConcurrentHashMap<String, AtomicInteger> errorCounts = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, LocalDateTime> lastErrorTimes = new ConcurrentHashMap<>();

    public CacheErrorHandler(
            @Value("${bookstore.cache.circuit-breaker-failure-threshold:5}") int failureThreshold,
            @Value("${bookstore.cache.circuit-breaker-recovery-timeout-ms:30000}") long circuitOpenMs,
            @Value("${bookstore.cache.circuit-breaker-failure-window-ms:60000}") long failureWindowMs) {
        this(failureThreshold, circuitOpenMs, failureWindowMs, Clock.systemDefaultZone());
    }

    /**
     * Test seam: an injectable {@link Clock} lets tests move the failure window forward without
     * sleeping. Production wiring defaults to {@link Clock#systemDefaultZone()}, so the external
     * behavior of every other constructor stays unchanged (issue #73 scope).
     */
    public CacheErrorHandler(int failureThreshold, long circuitOpenMs, long failureWindowMs, Clock clock) {
        this.failureThreshold = failureThreshold;
        this.circuitOpenDuration = Duration.ofMillis(circuitOpenMs);
        this.failureWindow = Duration.ofMillis(failureWindowMs);
        this.clock = clock;
    }

    public CacheErrorHandler(int failureThreshold, long circuitOpenMs) {
        this(failureThreshold, circuitOpenMs, 60_000L);
    }

    public CacheErrorHandler() {
        this(5, 30_000L, 60_000L);
    }

    public <T> T executeWithFallback(Supplier<T> operation, String operationName, String key) {
        return executeWithFallback(operation, operationName, key, () -> null);
    }

    public <T> T executeWithFallback(Supplier<T> operation, String operationName, String key, Supplier<T> fallback) {
        if (shouldBypassOperation()) {
            logger.debug("Circuit breaker is open, skipping cache operation: {} for key: {}", operationName, key);
            recordError(operationName, "Circuit breaker open");
            incrementFallbackRecommendation();
            return fallback.get();
        }

        try {
            T result = operation.get();
            recordSuccess(operationName);
            return result;
        } catch (Exception e) {
            handleCacheError(e, operationName, key);
            incrementFallbackRecommendation();
            return fallback.get();
        }
    }

    public boolean executeVoidOperation(Runnable operation, String operationName, String key) {
        if (shouldBypassOperation()) {
            logger.debug("Circuit breaker is open, skipping cache operation: {} for key: {}", operationName, key);
            recordError(operationName, "Circuit breaker open");
            incrementFallbackRecommendation();
            return false;
        }

        try {
            operation.run();
            recordSuccess(operationName);
            return true;
        } catch (Exception e) {
            handleCacheError(e, operationName, key);
            incrementFallbackRecommendation();
            return false;
        }
    }

    public void handleCacheError(Exception exception, String operationName, String key) {
        recordError(operationName, exception.getMessage());
        logger.warn(
                "Cache operation failed - Operation: {}, Key: {}, Error: {}",
                operationName,
                key,
                exception.getMessage());
        logger.debug("Cache operation failure details for {} with key {}", operationName, key, exception);

        if (circuitOpen) {
            // A failure observed while the breaker is Open/half-open (the single trial request):
            // revert to Open immediately and restart the recovery timer so a still-broken cache
            // is not hit again by every request (issue #56).
            openCircuit();
            return;
        }

        int failures = registerClosedStateFailure();
        if (failures >= failureThreshold) {
            openCircuit();
        }
    }

    /**
     * Counts a failure in the Closed state within the configured failure window
     * (bookstore.cache.circuit-breaker-failure-window-ms). Sporadic failures that spread beyond
     * the window must not accumulate: when the elapsed time since the window's first failure
     * exceeds the window, the counter restarts with the current failure.
     */
    private int registerClosedStateFailure() {
        LocalDateTime now = LocalDateTime.now(clock);
        LocalDateTime windowStart = firstFailureAt;
        if (windowStart == null || Duration.between(windowStart, now).compareTo(failureWindow) > 0) {
            firstFailureAt = now;
            consecutiveFailures.set(1);
            return 1;
        }
        return consecutiveFailures.incrementAndGet();
    }

    public boolean isCircuitOpen() {
        if (!circuitOpen) {
            return false;
        }

        LocalDateTime openedAt = circuitOpenedAt;
        if (openedAt != null
                && Duration.between(openedAt, LocalDateTime.now(clock)).compareTo(circuitOpenDuration) > 0) {
            logger.info("Circuit breaker entering half-open state - attempting cache recovery");
            return false;
        }

        return true;
    }

    /**
     * Gate used by the operation entry points. In the Closed state every request passes. Once the
     * recovery timer expires the breaker turns half-open and admits exactly one trial request;
     * all other requests are treated like the Open state and go straight to the fallback until
     * the trial resolves (success closes the circuit, failure reopens it with a fresh timer).
     * Unlike {@link #isCircuitOpen()} this method consumes the trial slot and must therefore only
     * be called by code paths that actually execute the protected operation.
     */
    private boolean shouldBypassOperation() {
        if (!circuitOpen) {
            return false;
        }

        LocalDateTime openedAt = circuitOpenedAt;
        if (openedAt != null
                && Duration.between(openedAt, LocalDateTime.now(clock)).compareTo(circuitOpenDuration) > 0) {
            if (halfOpenTrialActive.compareAndSet(false, true)) {
                logger.info("Circuit breaker entering half-open state - admitting a single trial request");
                return false;
            }
            logger.debug("Half-open circuit already has a trial request in flight - bypassing cache");
            return true;
        }

        return true;
    }

    public boolean checkCacheHealth(Supplier<Boolean> healthCheck) {
        try {
            if (healthCheck.get()) {
                closeCircuit();
                logger.info("Cache health check passed - circuit breaker closed");
                return true;
            } else {
                logger.debug("Cache health check failed - circuit breaker remains open");
                return false;
            }
        } catch (Exception e) {
            logger.warn("Cache health check threw exception: {}", e.getMessage());
            recordError("health-check", e.getMessage());
            return false;
        }
    }

    public boolean shouldFallbackToDatabase(String operationName) {
        AtomicInteger count = errorCounts.get(operationName);
        if (count != null && count.get() > failureThreshold / 2) {
            logger.debug("Frequent cache errors detected for {} - recommending database fallback", operationName);
            incrementFallbackRecommendation();
            return true;
        }
        return false;
    }

    public void recordSuccess(String operationName) {
        consecutiveFailures.set(0);
        firstFailureAt = null;
        errorCounts.remove(operationName);
        lastErrorTimes.remove(operationName);
        if (circuitOpen) {
            closeCircuit();
            logger.info("Cache circuit breaker closed after successful operation: {}", operationName);
        }
    }

    public String getCacheErrorStats() {
        StringBuilder stats = new StringBuilder();
        stats.append("Error Counts by Operation:\n");
        errorCounts.forEach((op, count) ->
                stats.append("  - ").append(op).append(": ").append(count.get()).append("\n"));
        stats.append("Last Error Times:\n");
        lastErrorTimes.forEach((op, time) ->
                stats.append("  - ").append(op).append(": ").append(time).append("\n"));
        return stats.toString();
    }

    public void resetErrorState() {
        consecutiveFailures.set(0);
        firstFailureAt = null;
        circuitOpen = false;
        circuitOpenedAt = null;
        halfOpenTrialActive.set(false);
        fallbackRecommendations.set(0);
        errorCounts.clear();
        lastErrorTimes.clear();
    }

    private void openCircuit() {
        circuitOpen = true;
        circuitOpenedAt = LocalDateTime.now(clock);
        halfOpenTrialActive.set(false);
        totalCircuitOpenings.incrementAndGet();
        logger.warn("Cache circuit breaker OPENED - bypassing the cache for the recovery timeout");
    }

    private void closeCircuit() {
        circuitOpen = false;
        consecutiveFailures.set(0);
        firstFailureAt = null;
        circuitOpenedAt = null;
        halfOpenTrialActive.set(false);
    }

    public int getConsecutiveFailureCount() {
        return consecutiveFailures.get();
    }

    public int getTotalCircuitOpenings() {
        return totalCircuitOpenings.get();
    }

    public int getFallbackRecommendationCount() {
        return fallbackRecommendations.get();
    }

    public int getTrackedErrorCount() {
        return errorCounts.values().stream().mapToInt(AtomicInteger::get).sum();
    }

    private void incrementFallbackRecommendation() {
        fallbackRecommendations.incrementAndGet();
    }

    private void recordError(String operationName, String errorMessage) {
        errorCounts.computeIfAbsent(operationName, key -> new AtomicInteger(0)).incrementAndGet();
        lastErrorTimes.put(operationName, LocalDateTime.now(clock));
        logger.debug("Recorded cache error for operation {}: {}", operationName, errorMessage);
    }
}
