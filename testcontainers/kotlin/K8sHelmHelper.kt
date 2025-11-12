package com.groom.infra.testcontainers

import java.io.File

/**
 * K8s 테스트 환경에서 Helm 차트를 배포하는 헬퍼 클래스
 */
object K8sHelmHelper {

    /**
     * 호스트에서 Helm 차트를 K3s 클러스터에 배포합니다.
     * K8sContainerExtension으로 시작된 K3s를 사용합니다.
     */
    fun installHelmChart(
        chartPath: String,
        releaseName: String,
        namespace: String = "default",
        values: Map<String, Any> = emptyMap(),
    ): Boolean {
        // kubeconfig를 임시 파일로 저장
        val kubeconfig = K8sContainerExtension.getKubeConfig()
        val kubeconfigFile = File.createTempFile("kubeconfig", ".yaml")
        kubeconfigFile.writeText(kubeconfig)
        kubeconfigFile.deleteOnExit()

        try {
            // Values를 --set 형식으로 변환
            val valuesArgs =
                values.entries.joinToString(" ") { (k, v) ->
                    "--set $k=$v"
                }

            // Helm install 명령 실행
            val command = buildList {
                add("helm")
                add("install")
                add(releaseName)
                add(chartPath)
                add("--kubeconfig")
                add(kubeconfigFile.absolutePath)
                add("--namespace")
                add(namespace)
                add("--create-namespace")
                add("--wait")
                add("--timeout")
                add("5m")
                if (values.isNotEmpty()) {
                    addAll(valuesArgs.split(" "))
                }
            }

            val process =
                ProcessBuilder(command)
                    .inheritIO()
                    .start()

            val exitCode = process.waitFor()
            return exitCode == 0
        } finally {
            kubeconfigFile.delete()
        }
    }

    /**
     * Helm 차트를 제거합니다.
     */
    fun uninstallHelmChart(
        releaseName: String,
        namespace: String = "default",
    ): Boolean {
        val kubeconfig = K8sContainerExtension.getKubeConfig()
        val kubeconfigFile = File.createTempFile("kubeconfig", ".yaml")
        kubeconfigFile.writeText(kubeconfig)
        kubeconfigFile.deleteOnExit()

        try {
            val process =
                ProcessBuilder(
                    "helm",
                    "uninstall",
                    releaseName,
                    "--kubeconfig",
                    kubeconfigFile.absolutePath,
                    "--namespace",
                    namespace,
                ).inheritIO()
                    .start()

            val exitCode = process.waitFor()
            return exitCode == 0
        } finally {
            kubeconfigFile.delete()
        }
    }

    /**
     * 네임스페이스를 생성합니다.
     */
    fun createNamespace(namespace: String): Boolean {
        val client = K8sContainerExtension.getKubernetesClient()
        return try {
            client
                .namespaces()
                .createOrReplace(
                    io.fabric8.kubernetes.api.model
                        .NamespaceBuilder()
                        .withNewMetadata()
                        .withName(namespace)
                        .endMetadata()
                        .build(),
                )
            true
        } catch (e: Exception) {
            println("Failed to create namespace $namespace: ${e.message}")
            false
        }
    }
}
