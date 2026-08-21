package com.sivalabs.bookstore.orders.infrastructure.grpc;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.jar.Attributes;
import java.util.jar.JarFile;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * Regression tests guarding the io.grpc dependency stack against partial/hidden upgrades.
 *
 * <p>The gRPC Java artifacts (grpc-api, grpc-protobuf, grpc-stub, grpc-netty, grpc-inprocess,
 * grpc-services, ...) must all resolve to the same version. When a single artifact (for example a
 * {@code grpc-protobuf} bump from 1.58.0 to 1.83.1) is upgraded alone, {@code grpc-api} follows it
 * and a version skew is created. grpc-java later versions removed internal classes that the
 * {@code grpc-spring-boot-starter} relied on (e.g. {@code io.grpc.InternalGlobalInterceptors}),
 * so the Spring application context fails to start and every gRPC integration test errors out
 * (see issue #27).
 *
 * <p>This test fails immediately on a skewed classpath without needing a container or a Spring
 * context, so any accidental partial grpc upgrade is caught by CI right away.
 */
@DisplayName("gRPC dependency stack compatibility (issue #27)")
class GrpcStackCompatibilityTests {

    /**
     * A distinct class from each io.grpc artifact. The class's code source points at the jar that
     * owns the artifact, from whose manifest we read {@code Implementation-Version}.
     */
    private static final Map<String, String> GRPC_PROBE_CLASSES = Map.of(
            "grpc-api", "io.grpc.Channel",
            "grpc-protobuf", "io.grpc.protobuf.ProtoUtils",
            "grpc-stub", "io.grpc.stub.AbstractStub",
            "grpc-netty", "io.grpc.netty.NettyChannelBuilder",
            "grpc-inprocess", "io.grpc.inprocess.InProcessChannelBuilder",
            "grpc-services", "io.grpc.protobuf.services.ProtoReflectionService");

    private static String implementationVersion(String className) throws Exception {
        Class<?> probe = Class.forName(className);
        var location = probe.getProtectionDomain().getCodeSource().getLocation().toURI();
        try (JarFile jar = new JarFile(location.getPath())) {
            Attributes attributes = jar.getManifest().getMainAttributes();
            return attributes.getValue(Attributes.Name.IMPLEMENTATION_VERSION);
        }
    }

    @Test
    @DisplayName("All io.grpc artifacts resolve to a single, consistent version")
    void grpcArtifactsAreVersionConsistent() throws Exception {
        Set<String> versions = new LinkedHashSet<>();
        for (Map.Entry<String, String> entry : GRPC_PROBE_CLASSES.entrySet()) {
            String version = implementationVersion(entry.getValue());
            assertThat(version)
                    .as("%s (%s) must expose an implementation version", entry.getKey(), entry.getValue())
                    .isNotBlank();
            versions.add(version);
            System.out.println("[grpc-stack] " + entry.getKey() + " -> " + version);
        }
        assertThat(versions)
                .as("all io.grpc artifacts must resolve to a single version")
                .hasSize(1);
    }
}
