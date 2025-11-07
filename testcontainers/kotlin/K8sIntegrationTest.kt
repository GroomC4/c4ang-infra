package com.groom.infra.testcontainers

import org.junit.jupiter.api.Tag
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles
import org.junit.jupiter.api.extension.ExtendWith

/**
 * K8s 통합 테스트를 위한 어노테이션
 *
 * Testcontainers K3s Module을 사용하여 K8s 환경을 제공합니다.
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
@Tag("k8s-integration-test")
@ActiveProfiles("k8s-test")
@SpringBootTest
@ExtendWith(K8sContainerExtension::class)
annotation class K8sIntegrationTest
