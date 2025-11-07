# K8s + Helm 인프라 전환 가이드

## 📋 개요

현재 Docker Compose 기반 인프라를 Kubernetes + Helm 환경으로 전환하는 가이드입니다.

**목표**: 옵션 4 (Hybrid 접근) 구현
- **단위/통합 테스트**: Testcontainers K3s Module (CI/CD 친화적)
- **E2E 테스트**: Docker Desktop Kubernetes + 실제 Helm 차트

---

## 🎯 전환 단계

### Phase 1: Helm Charts 작성 (1-2주)

#### 1. 디렉토리 구조 생성

```bash
cd c4ang-infra
mkdir -p helm/base/{postgresql,redis,kafka}
mkdir -p helm/services/{customer-service,store-service,product-service}
mkdir -p helm/test-infrastructure
mkdir -p k8s/{namespaces,configmaps,secrets}
```

#### 2. PostgreSQL Helm Chart 작성

**helm/base/postgresql/Chart.yaml**
```yaml
apiVersion: v2
name: postgresql
description: PostgreSQL with Primary-Replica replication
type: application
version: 1.0.0
appVersion: "17"

dependencies:
  - name: postgresql
    version: "15.5.0"
    repository: https://charts.bitnami.com/bitnami
```

**helm/base/postgresql/values.yaml**
```yaml
postgresql:
  auth:
    username: application
    password: application
    database: groom
    replicationUsername: repl_user
    replicationPassword: repl_password

  architecture: replication

  primary:
    persistence:
      enabled: true
      size: 10Gi
    resources:
      requests:
        memory: 256Mi
        cpu: 250m
      limits:
        memory: 512Mi
        cpu: 500m

  readReplicas:
    replicaCount: 1
    persistence:
      enabled: true
      size: 10Gi
    resources:
      requests:
        memory: 256Mi
        cpu: 250m
      limits:
        memory: 512Mi
        cpu: 500m
```

#### 3. Redis Helm Chart 작성

**helm/base/redis/Chart.yaml**
```yaml
apiVersion: v2
name: redis
description: Redis for caching
type: application
version: 1.0.0
appVersion: "7"

dependencies:
  - name: redis
    version: "19.5.0"
    repository: https://charts.bitnami.com/bitnami
```

**helm/base/redis/values.yaml**
```yaml
redis:
  auth:
    enabled: false

  master:
    persistence:
      enabled: true
      size: 5Gi
    resources:
      requests:
        memory: 128Mi
        cpu: 100m
      limits:
        memory: 256Mi
        cpu: 200m
```

#### 4. Customer Service Helm Chart 작성

**helm/services/customer-service/Chart.yaml**
```yaml
apiVersion: v2
name: customer-service
description: Customer Service Microservice
type: application
version: 1.0.0
appVersion: "1.0.0"

dependencies:
  - name: postgresql
    version: "1.0.0"
    repository: "file://../../base/postgresql"
    condition: postgresql.enabled
  - name: redis
    version: "1.0.0"
    repository: "file://../../base/redis"
    condition: redis.enabled
```

**helm/services/customer-service/values.yaml**
```yaml
replicaCount: 2

image:
  repository: c4ang/customer-service
  pullPolicy: IfNotPresent
  tag: "latest"

service:
  type: ClusterIP
  port: 8080
  targetPort: 8080

ingress:
  enabled: true
  className: "nginx"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: api.c4ang.com
      paths:
        - path: /api/v1/customers
          pathType: Prefix
  tls:
    - secretName: customer-service-tls
      hosts:
        - api.c4ang.com

resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 1Gi
    cpu: 500m

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

env:
  - name: SPRING_PROFILES_ACTIVE
    value: "prod"
  - name: SPRING_DATASOURCE_PRIMARY_URL
    value: "jdbc:postgresql://postgresql-primary:5432/customer_db"
  - name: SPRING_DATASOURCE_REPLICA_URL
    value: "jdbc:postgresql://postgresql-replica:5432/customer_db"
  - name: SPRING_DATASOURCE_USERNAME
    valueFrom:
      secretKeyRef:
        name: customer-service-db-secret
        key: username
  - name: SPRING_DATASOURCE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: customer-service-db-secret
        key: password
  - name: SPRING_DATA_REDIS_HOST
    value: "redis-master"
  - name: SPRING_DATA_REDIS_PORT
    value: "6379"

postgresql:
  enabled: true
  auth:
    database: customer_db

redis:
  enabled: true
```

**helm/services/customer-service/templates/deployment.yaml**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "customer-service.fullname" . }}
  labels:
    {{- include "customer-service.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "customer-service.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "customer-service.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - name: http
          containerPort: {{ .Values.service.targetPort }}
          protocol: TCP
        env:
        {{- toYaml .Values.env | nindent 8 }}
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: http
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
```

**helm/services/customer-service/templates/service.yaml**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "customer-service.fullname" . }}
  labels:
    {{- include "customer-service.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
      name: http
  selector:
    {{- include "customer-service.selectorLabels" . | nindent 4 }}
```

**helm/services/customer-service/templates/ingress.yaml**
```yaml
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "customer-service.fullname" . }}
  labels:
    {{- include "customer-service.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  {{- if .Values.ingress.tls }}
  tls:
    {{- range .Values.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ include "customer-service.fullname" $ }}
                port:
                  number: {{ $.Values.service.port }}
          {{- end }}
    {{- end }}
{{- end }}
```

**helm/services/customer-service/templates/hpa.yaml**
```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "customer-service.fullname" . }}
  labels:
    {{- include "customer-service.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "customer-service.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    {{- if .Values.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if .Values.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end }}
```

**helm/services/customer-service/templates/_helpers.tpl**
```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "customer-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "customer-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "customer-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "customer-service.labels" -}}
helm.sh/chart: {{ include "customer-service.chart" . }}
{{ include "customer-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "customer-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "customer-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

#### 5. 통합 테스트용 Helm Chart

**helm/test-infrastructure/Chart.yaml**
```yaml
apiVersion: v2
name: test-infrastructure
description: Infrastructure for integration tests
type: application
version: 1.0.0

dependencies:
  - name: postgresql
    version: "1.0.0"
    repository: "file://../base/postgresql"
  - name: redis
    version: "1.0.0"
    repository: "file://../base/redis"
```

**helm/test-infrastructure/values.yaml**
```yaml
postgresql:
  auth:
    username: test
    password: test
    database: groom

  primary:
    persistence:
      enabled: false  # 테스트용이므로 영속성 비활성화
    resources:
      requests:
        memory: 128Mi
        cpu: 100m

redis:
  master:
    persistence:
      enabled: false
    resources:
      requests:
        memory: 64Mi
        cpu: 50m
```

---

### Phase 2: Testcontainers K3s Module 구현 (1주)

#### 1. K3s 의존성 추가

각 서비스의 **build.gradle.kts**에 추가:
```kotlin
dependencies {
    // 기존 Testcontainers
    testImplementation("org.springframework.boot:spring-boot-testcontainers")
    testImplementation("org.testcontainers:junit-jupiter")
    testImplementation("org.testcontainers:postgresql")
    testImplementation("org.testcontainers:testcontainers")

    // K3s Module 추가
    testImplementation("org.testcontainers:k3s:1.19.7")
    testImplementation("io.fabric8:kubernetes-client:6.10.0")
}
```

#### 2. K8sContainerExtension 생성

**testcontainers/kotlin/K8sContainerExtension.kt**
```kotlin
package com.groom.infra.testcontainers

import io.fabric8.kubernetes.client.Config
import io.fabric8.kubernetes.client.KubernetesClientBuilder
import org.junit.jupiter.api.extension.BeforeAllCallback
import org.junit.jupiter.api.extension.ExtensionContext
import org.testcontainers.k3s.K3sContainer
import org.testcontainers.utility.DockerImageName
import java.time.Duration

/**
 * K8s 통합 테스트를 위한 공유 K3s 컨테이너 Extension
 *
 * Testcontainers K3s Module을 사용하여 경량 Kubernetes 클러스터를 제공합니다.
 *
 * 사용 예시:
 * ```kotlin
 * @K8sIntegrationTest
 * @SpringBootTest
 * class CustomerServiceK8sIntegrationTest {
 *     @Test
 *     fun `K8s 환경에서 통합 테스트`() {
 *         val client = K8sContainerExtension.getKubernetesClient()
 *         // 테스트 로직
 *     }
 * }
 * 
 */
class K8sContainerExtension : BeforeAllCallback {
    companion object {
        @Volatile
        private var initialized = false

        private lateinit var k3sContainer: K3sContainer
        private lateinit var kubeConfigYaml: String

        /**
         * Kubernetes 클라이언트를 반환합니다.
         */
        @JvmStatic
        fun getKubernetesClient() = KubernetesClientBuilder()
            .withConfig(Config.fromKubeconfig(kubeConfigYaml))
            .build()

        /**
         * Kubeconfig YAML을 반환합니다.
         */
        @JvmStatic
        fun getKubeConfig(): String = kubeConfigYaml

        /**
         * K8s API Server URL을 반환합니다.
         */
        @JvmStatic
        fun getApiServerUrl(): String = k3sContainer.kubernetesUrl

        /**
         * Helm 차트를 배포합니다.
         */
        @JvmStatic
        fun installHelmChart(
            chartPath: String,
            releaseName: String,
            namespace: String = "default",
            values: Map<String, Any> = emptyMap()
        ) {
            val valuesArgs = values.entries.joinToString(" ") { (k, v) ->
                "--set $k=$v"
            }

            val helmInstallCmd = """
                helm install $releaseName $chartPath \
                    --namespace $namespace \
                    --create-namespace \
                    $valuesArgs \
                    --wait
            """.trimIndent()

            k3sContainer.execInContainer(
                "/bin/sh", "-c", helmInstallCmd
            )
        }

        /**
         * Helm 차트를 제거합니다.
         */
        @JvmStatic
        fun uninstallHelmChart(releaseName: String, namespace: String = "default") {
            k3sContainer.execInContainer(
                "/bin/sh", "-c",
                "helm uninstall $releaseName --namespace $namespace"
            )
        }
    }

    override fun beforeAll(context: ExtensionContext) {
        synchronized(K8sContainerExtension::class.java) {
            if (!initialized) {
                println("🚀 Starting shared K3s container for integration tests...")

                k3sContainer = K3sContainer(DockerImageName.parse("rancher/k3s:v1.28.5-k3s1"))
                    .withStartupTimeout(Duration.ofMinutes(2))

                k3sContainer.start()
                kubeConfigYaml = k3sContainer.kubeConfigYaml
                initialized = true

                // JVM 종료 시 컨테이너 정리
                Runtime.getRuntime().addShutdownHook(
                    Thread {
                        println("🛑 Stopping shared K3s container...")
                        k3sContainer.stop()
                    }
                )

                println("✅ K3s container started successfully")
                println("📍 API Server: ${k3sContainer.kubernetesUrl}")
            }
        }
    }
}
```

#### 3. K8sIntegrationTest 어노테이션

**testcontainers/kotlin/K8sIntegrationTest.kt**
```kotlin
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
```

#### 4. 각 서비스에서 사용

**customer-service-app/src/test/kotlin/.../CustomerServiceK8sIntegrationTest.kt**
```kotlin
package com.example.customerservice

import com.groom.infra.testcontainers.K8sContainerExtension
import com.groom.infra.testcontainers.K8sIntegrationTest
import io.fabric8.kubernetes.api.model.NamespaceBuilder
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test

@K8sIntegrationTest
class CustomerServiceK8sIntegrationTest {

    companion object {
        @BeforeAll
        @JvmStatic
        fun setupK8sResources() {
            val client = K8sContainerExtension.getKubernetesClient()

            // 네임스페이스 생성
            client.namespaces().resource(
                NamespaceBuilder()
                    .withNewMetadata()
                        .withName("customer-test")
                    .endMetadata()
                    .build()
            ).create()

            // Helm 차트 배포 (infra-config에서)
            K8sContainerExtension.installHelmChart(
                chartPath = "../infra-config/helm/test-infrastructure",
                releaseName = "test-infra",
                namespace = "customer-test",
                values = mapOf(
                    "postgresql.auth.database" to "customer_db",
                    "postgresql.auth.username" to "test",
                    "postgresql.auth.password" to "test"
                )
            )
        }
    }

    @Test
    fun `Customer API가 K8s 환경에서 정상 동작한다`() {
        // 테스트 로직
        val client = K8sContainerExtension.getKubernetesClient()

        // PostgreSQL Pod가 Running 상태인지 확인
        val pods = client.pods()
            .inNamespace("customer-test")
            .withLabel("app.kubernetes.io/name", "postgresql")
            .list()

        assert(pods.items.isNotEmpty())
        assert(pods.items.first().status.phase == "Running")
    }
}
```

#### 5. Gradle 태스크 설정

**build.gradle.kts**
```kotlin
tasks.withType<Test> {
    useJUnitPlatform {
        // 일반 통합 테스트 (Docker Compose 기반)
        includeTags("integration-test")
        excludeTags("k8s-integration-test", "e2e-test")
    }
}

// K8s 통합 테스트 전용 태스크
val k8sIntegrationTest by tasks.registering(Test::class) {
    description = "Runs K8s integration tests (K3s)"
    group = "verification"

    useJUnitPlatform {
        includeTags("k8s-integration-test")
    }

    // K3s 시작 시간 고려하여 타임아웃 증가
    testLogging {
        events("passed", "skipped", "failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }

    shouldRunAfter(tasks.test)
}

// E2E 테스트 태스크
val e2eTest by tasks.registering(Test::class) {
    description = "Runs E2E tests (Docker Desktop K8s)"
    group = "verification"

    useJUnitPlatform {
        includeTags("e2e-test")
    }

    // 로컬 K8s가 필요함을 체크
    doFirst {
        val result = exec {
            commandLine("kubectl", "cluster-info")
            isIgnoreExitValue = true
        }
        if (result.exitValue != 0) {
            throw GradleException(
                "Docker Desktop Kubernetes is not available. " +
                "Please enable it in Docker Desktop settings."
            )
        }
    }

    shouldRunAfter(k8sIntegrationTest)
}
```

---

### Phase 3: Docker Desktop Kubernetes E2E 테스트 (1주)

#### 1. LocalK8sTestSupport 유틸리티

**testcontainers/kotlin/LocalK8sTestSupport.kt**
```kotlin
package com.groom.infra.testcontainers

import java.io.File

/**
 * Docker Desktop Kubernetes를 사용한 로컬 E2E 테스트 지원
 *
 * 사전 요구사항:
 * - Docker Desktop Kubernetes 활성화
 * - kubectl 설치
 * - Helm 설치
 */
object LocalK8sTestSupport {

    fun isLocalK8sAvailable(): Boolean {
        return try {
            val process = ProcessBuilder("kubectl", "cluster-info")
                .redirectErrorStream(true)
                .start()
            process.waitFor() == 0
        } catch (e: Exception) {
            false
        }
    }

    fun setupTestInfra(namespace: String = "e2e-test") {
        require(isLocalK8sAvailable()) {
            "Docker Desktop Kubernetes is not available. " +
            "Please enable it in Docker Desktop settings."
        }

        // 네임스페이스 생성
        exec("kubectl", "create", "namespace", namespace, "--dry-run=client", "-o", "yaml", "|", "kubectl", "apply", "-f", "-")

        // Helm 차트 배포
        val helmInstall = ProcessBuilder(
            "helm", "install", "e2e-infra",
            "../infra-config/helm/test-infrastructure",
            "--namespace", namespace,
            "--create-namespace",
            "--wait",
            "--timeout", "5m"
        ).inheritIO().start()

        require(helmInstall.waitFor() == 0) {
            "Failed to install test infrastructure"
        }

        println("✅ E2E test infrastructure installed successfully")
    }

    fun teardownTestInfra(namespace: String = "e2e-test") {
        ProcessBuilder(
            "helm", "uninstall", "e2e-infra",
            "--namespace", namespace
        ).inheritIO().start().waitFor()

        ProcessBuilder(
            "kubectl", "delete", "namespace", namespace
        ).inheritIO().start().waitFor()

        println("🛑 E2E test infrastructure removed")
    }

    private fun exec(vararg command: String): Int {
        return ProcessBuilder(*command)
            .inheritIO()
            .start()
            .waitFor()
    }
}
```

#### 2. E2E 테스트 Base 클래스

**testcontainers/kotlin/E2ETestBase.kt**
```kotlin
package com.groom.infra.testcontainers

import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Tag

@Tag("e2e-test")
abstract class E2ETestBase {

    companion object {
        @BeforeAll
        @JvmStatic
        fun setUpE2EInfrastructure() {
            println("🚀 Setting up E2E test infrastructure...")
            LocalK8sTestSupport.setupTestInfra()
        }

        @AfterAll
        @JvmStatic
        fun tearDownE2EInfrastructure() {
            println("🛑 Tearing down E2E test infrastructure...")
            LocalK8sTestSupport.teardownTestInfra()
        }
    }
}
```

#### 3. E2E 테스트 작성

**customer-service-app/src/test/kotlin/.../CustomerServiceE2ETest.kt**
```kotlin
package com.example.customerservice

import com.groom.infra.testcontainers.E2ETestBase
import io.restassured.RestAssured
import io.restassured.http.ContentType
import org.hamcrest.Matchers.*
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.server.LocalServerPort

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class CustomerServiceE2ETest : E2ETestBase() {

    @LocalServerPort
    private var port: Int = 0

    companion object {
        @BeforeAll
        @JvmStatic
        fun setUp() {
            // 필요한 환경 변수 설정
            System.setProperty("spring.profiles.active", "e2e-test")
        }
    }

    @Test
    fun `E2E - 고객 생성부터 조회까지 전체 플로우 테스트`() {
        RestAssured.baseURI = "http://localhost:$port"

        // 1. 고객 생성
        val customerId = RestAssured.given()
            .contentType(ContentType.JSON)
            .body("""
                {
                    "name": "홍길동",
                    "email": "hong@example.com",
                    "phoneNumber": "010-1234-5678"
                }
            """.trimIndent())
            .`when`()
            .post("/api/v1/customers")
            .then()
            .statusCode(201)
            .body("name", equalTo("홍길동"))
            .extract()
            .path<String>("id")

        // 2. 고객 조회
        RestAssured.given()
            .`when`()
            .get("/api/v1/customers/$customerId")
            .then()
            .statusCode(200)
            .body("id", equalTo(customerId))
            .body("name", equalTo("홍길동"))
            .body("email", equalTo("hong@example.com"))
    }
}
```

---

### Phase 4: CI/CD 파이프라인 설정 (1주)

#### GitHub Actions 워크플로우

**.github/workflows/test.yml**
```yaml
name: Integration & E2E Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Run unit tests
        run: ./gradlew test

  integration-tests-docker-compose:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Run integration tests (Docker Compose)
        run: ./gradlew test --tests '*IntegrationTest'

  integration-tests-k8s:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Install Helm
        uses: azure/setup-helm@v4
        with:
          version: '3.14.0'

      - name: Run K8s integration tests (K3s)
        run: ./gradlew k8sIntegrationTest

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: k8s-test-results
          path: build/test-results/

  e2e-tests:
    runs-on: ubuntu-latest
    needs: [integration-tests-docker-compose, integration-tests-k8s]
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'

      - name: Set up Kind
        uses: helm/kind-action@v1.10.0
        with:
          cluster_name: e2e-cluster

      - name: Install Helm
        uses: azure/setup-helm@v4
        with:
          version: '3.14.0'

      - name: Run E2E tests
        run: ./gradlew e2eTest
```

---

## 📦 배포 가이드

### 로컬 개발 환경 (Docker Desktop Kubernetes)

```bash
# 1. Docker Desktop Kubernetes 활성화
# Docker Desktop > Settings > Kubernetes > Enable Kubernetes

# 2. 네임스페이스 생성
kubectl create namespace dev

# 3. Helm 차트 배포
cd infra-config/helm/services/customer-service
helm install customer-service . \
    --namespace dev \
    --values values-dev.yaml \
    --create-namespace

# 4. 상태 확인
kubectl get pods -n dev
kubectl get svc -n dev

# 5. 로컬 접속 (Port Forward)
kubectl port-forward svc/customer-service 8080:8080 -n dev
```

### 프로덕션 배포 (EKS, GKE 등)

```bash
# 1. Helm 차트 배포
helm install customer-service ./helm/services/customer-service \
    --namespace prod \
    --values values-prod.yaml \
    --create-namespace

# 2. Ingress 설정 확인
kubectl get ingress -n prod

# 3. 롤링 업데이트
helm upgrade customer-service ./helm/services/customer-service \
    --namespace prod \
    --values values-prod.yaml \
    --set image.tag=v1.2.0

# 4. 롤백 (필요 시)
helm rollback customer-service -n prod
```

---

## 🧪 테스트 전략 요약

| 테스트 유형 | 도구 | 실행 시점 | 목적 |
|-----------|------|----------|------|
| 단위 테스트 | JUnit5 + MockK | 로컬 개발 | 개별 클래스/메서드 검증 |
| 통합 테스트 (Docker Compose) | Testcontainers | 로컬 개발, CI | DB/Redis 연동 검증 (빠름) |
| 통합 테스트 (K3s) | Testcontainers K3s | CI/CD | K8s 환경 검증 (중간) |
| E2E 테스트 | Docker Desktop K8s + Helm | 배포 전 | 전체 플로우 검증 (느림) |

---

## 📝 체크리스트

### Helm Charts 작성
- [ ] PostgreSQL Helm Chart 작성
- [ ] Redis Helm Chart 작성
- [ ] Customer Service Helm Chart 작성
- [ ] 테스트 인프라 Helm Chart 작성
- [ ] 각 서비스별 Helm Chart 작성 (Store, Product, Order 등)

### Testcontainers K3s Module
- [ ] K8sContainerExtension 구현
- [ ] K8sIntegrationTest 어노테이션 추가
- [ ] Gradle 태스크 설정 (k8sIntegrationTest)
- [ ] 각 서비스에 K8s 통합 테스트 작성

### Docker Desktop Kubernetes E2E
- [ ] LocalK8sTestSupport 구현
- [ ] E2ETestBase 추가
- [ ] E2E 테스트 작성
- [ ] Gradle 태스크 설정 (e2eTest)

### CI/CD
- [ ] GitHub Actions 워크플로우 작성
- [ ] 테스트 단계별 분리 (unit → integration → e2e)
- [ ] 아티팩트 업로드 설정

### 배포
- [ ] 로컬 K8s 배포 가이드 작성
- [ ] 프로덕션 배포 스크립트 작성
- [ ] 롤백 절차 문서화

---

## 🔗 참고 자료

- [Testcontainers K3s Module](https://java.testcontainers.org/modules/k3s/)
- [Helm Charts 공식 문서](https://helm.sh/docs/)
- [Kubernetes 공식 문서](https://kubernetes.io/docs/)
- [Bitnami Helm Charts](https://github.com/bitnami/charts)
- [Fabric8 Kubernetes Client](https://github.com/fabric8io/kubernetes-client)

---

**작성일**: 2025-11-05
**작성자**: Claude Code
**버전**: 1.0.0