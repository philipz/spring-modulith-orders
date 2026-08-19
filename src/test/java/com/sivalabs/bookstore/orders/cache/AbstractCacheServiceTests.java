package com.sivalabs.bookstore.orders.cache;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.hazelcast.map.IMap;
import com.hazelcast.map.LocalMapStats;
import java.util.Arrays;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

@DisplayName("AbstractCacheService Unit Tests")
class AbstractCacheServiceTests {

    private IMap<String, Object> cache;
    private LocalMapStats localStats;
    private CacheErrorHandler errorHandler;
    private TestCacheService service;

    private static class TestCacheService extends AbstractCacheService<String, String> {

        TestCacheService(IMap<String, Object> cache, CacheErrorHandler errorHandler) {
            super(cache, errorHandler, String.class);
        }

        @Override
        protected String getCacheDisplayName() {
            return "TestCache";
        }

        @Override
        protected String createHealthCheckKey() {
            return "health-check-key";
        }

        // Expose protected helpers for verification within the same package.
        boolean doCacheEntity(String key, String entity) {
            return cacheEntity(key, entity);
        }

        boolean doUpdateCachedEntity(String key, String entity) {
            return updateCachedEntity(key, entity);
        }

        String doSafeCast(Object value, String key) {
            return safeCast(value, key);
        }
    }

    @BeforeEach
    void setUp() {
        cache = mock(IMap.class);
        when(cache.getName()).thenReturn("orders-cache");
        localStats = mock(LocalMapStats.class);
        errorHandler = new CacheErrorHandler();
        service = new TestCacheService(cache, errorHandler);
    }

    @Nested
    @DisplayName("getCacheStats")
    class GetCacheStats {

        @Test
        @DisplayName("Should include cache name, size and local map statistics")
        void shouldIncludeCacheDetails() {
            when(cache.size()).thenReturn(42);
            when(cache.getLocalMapStats()).thenReturn(localStats);
            when(localStats.getOwnedEntryCount()).thenReturn(30L);
            when(localStats.getBackupEntryCount()).thenReturn(10L);
            when(localStats.getHits()).thenReturn(99L);
            when(localStats.getGetOperationCount()).thenReturn(150L);
            when(localStats.getPutOperationCount()).thenReturn(60L);

            String stats = service.getCacheStats();

            assertThat(stats).contains("TestCache Cache Statistics:");
            assertThat(stats).contains("Cache Name: orders-cache");
            assertThat(stats).contains("Cache Size: 42");
            assertThat(stats).contains("Owned Entry Count: 30");
            assertThat(stats).contains("Backup Entry Count: 10");
            assertThat(stats).contains("Hits: 99");
            assertThat(stats).contains("Get Operations: 150");
            assertThat(stats).contains("Put Operations: 60");
        }

        @Test
        @DisplayName("Should omit local map statistics when unavailable")
        void shouldOmitLocalStatsWhenNull() {
            when(cache.size()).thenReturn(3);
            when(cache.getLocalMapStats()).thenReturn(null);

            String stats = service.getCacheStats();

            assertThat(stats).contains("Cache Name: orders-cache");
            assertThat(stats).contains("Cache Size: 3");
            assertThat(stats).doesNotContain("Local Map Stats:");
        }

        @Test
        @DisplayName("Should fall back to the unavailable message when the operation fails")
        void shouldFallbackWhenOperationFails() {
            when(cache.size()).thenThrow(new RuntimeException("cache unavailable"));

            String stats = service.getCacheStats();

            assertThat(stats).isEqualTo("Cache stats unavailable due to error\n");
        }

        @Test
        @DisplayName("Should fall back to the unavailable message when the circuit breaker is open")
        void shouldFallbackWhenCircuitOpen() {
            openCircuit();

            String stats = service.getCacheStats();

            assertThat(stats).isEqualTo("Cache stats unavailable due to error\n");
        }
    }

    @Nested
    @DisplayName("isHealthy")
    class IsHealthy {

        @Test
        @DisplayName("Should report healthy when the cache put/get/remove round-trip succeeds")
        void shouldReportHealthyOnRoundTrip() {
            when(cache.get("health-check-key")).thenReturn("health-check-value");

            boolean healthy = service.isHealthy();

            assertThat(healthy).isTrue();
            verify(cache).put("health-check-key", "health-check-value");
            verify(cache).remove("health-check-key");
        }

        @Test
        @DisplayName("Should report unhealthy when the cached value does not round-trip")
        void shouldReportUnhealthyWhenValueMismatches() {
            when(cache.get("health-check-key")).thenReturn("other-value");

            boolean healthy = service.isHealthy();

            assertThat(healthy).isFalse();
        }

        @Test
        @DisplayName("Should report unhealthy when the cache operation throws")
        void shouldReportUnhealthyWhenCacheThrows() {
            when(cache.put(anyString(), any())).thenThrow(new RuntimeException("cache unavailable"));

            boolean healthy = service.isHealthy();

            assertThat(healthy).isFalse();
        }
    }

    @Nested
    @DisplayName("Circuit breaker status")
    class CircuitBreaker {

        @Test
        @DisplayName("Should show CLOSED status and delegate when the circuit is closed")
        void shouldShowClosedStatus() {
            String status = service.getCircuitBreakerStatus();

            assertThat(status).contains("Circuit State: CLOSED (Cache Active)");
            assertThat(service.isCircuitBreakerOpen()).isFalse();
            assertThat(service.shouldFallbackToDatabase("read")).isFalse();
        }

        @Test
        @DisplayName("Should show OPEN status and recommend fallback when the circuit is open")
        void shouldShowOpenStatus() {
            openCircuit();

            String status = service.getCircuitBreakerStatus();
            boolean open = service.isCircuitBreakerOpen();
            boolean shouldFallback = service.shouldFallbackToDatabase("read");

            assertThat(status).contains("Circuit State: OPEN (Bypassing Cache)");
            assertThat(status).contains("Error Statistics:");
            assertThat(open).isTrue();
            assertThat(shouldFallback).isTrue();
        }

        @Test
        @DisplayName("Should reset tracked error state when the circuit is closed")
        void shouldResetCircuitBreaker() {
            errorHandler.handleCacheError(new RuntimeException("err"), "read", "k1");
            assertThat(errorHandler.getConsecutiveFailureCount()).isEqualTo(1);

            boolean reset = service.resetCircuitBreaker();

            assertThat(reset).isTrue();
            assertThat(errorHandler.getConsecutiveFailureCount()).isZero();
            assertThat(errorHandler.getTrackedErrorCount()).isZero();
            assertThat(service.isCircuitBreakerOpen()).isFalse();
        }

        @Test
        @DisplayName("Should recommend database fallback when frequent errors are tracked")
        void shouldRecommendFallbackOnFrequentErrors() {
            // Two failures against the default threshold of 5 exceeds threshold / 2 (2 > 2 is false,
            // so use three failures to make the recommendation deterministic).
            errorHandler.handleCacheError(new RuntimeException("err"), "read", "k1");
            errorHandler.handleCacheError(new RuntimeException("err"), "read", "k2");
            errorHandler.handleCacheError(new RuntimeException("err"), "read", "k3");

            boolean shouldFallback = service.shouldFallbackToDatabase("read");

            assertThat(shouldFallback).isTrue();
        }
    }

    @Nested
    @DisplayName("existsInCache and removeFromCache")
    class ExistenceAndRemoval {

        @Test
        @DisplayName("Should report whether a key exists in the cache")
        void shouldReportExistence() {
            when(cache.containsKey("k1")).thenReturn(true);
            when(cache.containsKey("k2")).thenReturn(false);

            assertThat(service.existsInCache("k1")).isTrue();
            assertThat(service.existsInCache("k2")).isFalse();
        }

        @Test
        @DisplayName("Should assume the key does not exist when the lookup fails")
        void shouldAssumeFalseWhenLookupFails() {
            when(cache.containsKey("k1")).thenThrow(new RuntimeException("cache unavailable"));

            boolean exists = service.existsInCache("k1");

            assertThat(exists).isFalse();
        }

        @Test
        @DisplayName("Should remove a present key and report success")
        void shouldRemovePresentKey() {
            when(cache.remove("k1")).thenReturn("order-1");

            boolean removed = service.removeFromCache("k1");

            assertThat(removed).isTrue();
            verify(cache).remove("k1");
        }

        @Test
        @DisplayName("Should still report operation success and attempt removal for an absent key")
        void shouldRemoveAbsentKey() {
            when(cache.remove("k1")).thenReturn(null);

            boolean removed = service.removeFromCache("k1");

            // removeFromCache wraps the removal in a void operation: it reports success as long as the
            // removal did not throw, even when no entry was actually present.
            assertThat(removed).isTrue();
            verify(cache).remove("k1");
        }

        @Test
        @DisplayName("Should report failure when removal throws")
        void shouldReportRemovalFailure() {
            when(cache.remove("k1")).thenThrow(new RuntimeException("cache unavailable"));

            boolean removed = service.removeFromCache("k1");

            assertThat(removed).isFalse();
        }
    }

    @Nested
    @DisplayName("warmUpCache")
    class WarmUp {

        @Test
        @DisplayName("Should count keys that are present in the cache")
        void shouldCountWarmedKeys() {
            when(cache.get("k1")).thenReturn("order-1");
            when(cache.get("k2")).thenReturn(null);
            when(cache.get("k3")).thenReturn("order-3");

            int warmed = service.warmUpCache(Arrays.asList("k1", "k2", "k3"));

            assertThat(warmed).isEqualTo(2);
        }

        @Test
        @DisplayName("Should not count a key as warmed when the lookup fails")
        void shouldNotCountFailedLookup() {
            when(cache.get("k1")).thenThrow(new RuntimeException("cache unavailable"));
            when(cache.get("k2")).thenReturn("order-2");

            int warmed = service.warmUpCache(List.of("k1", "k2"));

            assertThat(warmed).isEqualTo(1);
        }
    }

    @Nested
    @DisplayName("cacheEntity")
    class CacheEntity {

        @Test
        @DisplayName("Should reject a null entity")
        void shouldRejectNullEntity() {
            boolean cached = service.doCacheEntity("k1", null);

            assertThat(cached).isFalse();
            verify(cache, never()).put(anyString(), any());
        }

        @Test
        @DisplayName("Should put a non-null entity and report success")
        void shouldCacheNonNullEntity() {
            boolean cached = service.doCacheEntity("k1", "order-1");

            assertThat(cached).isTrue();
            verify(cache).put("k1", "order-1");
        }

        @Test
        @DisplayName("Should report failure when the put throws")
        void shouldReportFailureOnPutError() {
            when(cache.put(anyString(), any())).thenThrow(new RuntimeException("cache unavailable"));

            boolean cached = service.doCacheEntity("k1", "order-1");

            assertThat(cached).isFalse();
        }
    }

    @Nested
    @DisplayName("updateCachedEntity")
    class UpdateCachedEntity {

        @Test
        @DisplayName("Should update an existing key")
        void shouldUpdateExistingKey() {
            when(cache.containsKey("k1")).thenReturn(true);

            boolean updated = service.doUpdateCachedEntity("k1", "order-1");

            assertThat(updated).isTrue();
            verify(cache).put("k1", "order-1");
        }

        @Test
        @DisplayName("Should not put when the key is absent")
        void shouldNotUpdateAbsentKey() {
            when(cache.containsKey("k1")).thenReturn(false);

            boolean updated = service.doUpdateCachedEntity("k1", "order-1");

            assertThat(updated).isTrue();
            verify(cache, never()).put(anyString(), any());
        }

        @Test
        @DisplayName("Should reject a null entity")
        void shouldRejectNullEntity() {
            boolean updated = service.doUpdateCachedEntity("k1", null);

            assertThat(updated).isFalse();
            verify(cache, never()).containsKey(anyString());
        }
    }

    @Nested
    @DisplayName("safeCast")
    class SafeCast {

        @Test
        @DisplayName("Should return null for a null value")
        void shouldReturnNullForNullValue() {
            String result = service.doSafeCast(null, "k1");

            assertThat(result).isNull();
        }

        @Test
        @DisplayName("Should return null when the value type does not match")
        void shouldReturnNullOnTypeMismatch() {
            String result = service.doSafeCast(Integer.valueOf(42), "k1");

            assertThat(result).isNull();
        }

        @Test
        @DisplayName("Should return the value when the type matches")
        void shouldCastMatchingType() {
            String result = service.doSafeCast("order-1", "k1");

            assertThat(result).isEqualTo("order-1");
        }
    }

    private void openCircuit() {
        // Default CacheErrorHandler failure threshold is 5.
        for (int i = 0; i < 5; i++) {
            errorHandler.handleCacheError(new RuntimeException("cache unavailable"), "read", "key-" + i);
        }
        assertThat(errorHandler.isCircuitOpen()).isTrue();
    }
}
