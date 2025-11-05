package com.groom.infra.testcontainers

import org.junit.jupiter.api.Tag
import org.springframework.test.context.ActiveProfiles

/**
 * 통합 테스트를 위한 공통 어노테이션
 *
 * 각 서비스에서 자신의 ContainerExtension과 함께 사용합니다:
 *
 * ```kotlin
 * @IntegrationTest
 * @SpringBootTest
 * @AutoConfigureMockMvc
 * @ExtendWith(StoreServiceContainerExtension::class)
 * class StoreControllerIntegrationTest {
 *     // 테스트 코드
 * }
 * ```
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.RUNTIME)
@Tag("integration-test")
@ActiveProfiles("test")
annotation class IntegrationTest