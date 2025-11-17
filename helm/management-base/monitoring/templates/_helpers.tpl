{{/*
Expand the name of the chart.
*/}}
{{- define "monitoring.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "monitoring.fullname" -}}
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
{{- define "monitoring.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "monitoring.labels" -}}
helm.sh/chart: {{ include "monitoring.chart" . }}
{{ include "monitoring.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "monitoring.selectorLabels" -}}
app.kubernetes.io/name: {{ include "monitoring.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Alloy labels
*/}}
{{- define "monitoring.alloy.labels" -}}
{{ include "monitoring.labels" . }}
app.kubernetes.io/component: alloy
{{- end }}

{{/*
Alloy selector labels
*/}}
{{- define "monitoring.alloy.selectorLabels" -}}
{{ include "monitoring.selectorLabels" . }}
app.kubernetes.io/component: alloy
{{- end }}

{{/*
Prometheus labels
*/}}
{{- define "monitoring.prometheus.labels" -}}
{{ include "monitoring.labels" . }}
app.kubernetes.io/component: prometheus
{{- end }}

{{/*
Prometheus selector labels
*/}}
{{- define "monitoring.prometheus.selectorLabels" -}}
{{ include "monitoring.selectorLabels" . }}
app.kubernetes.io/component: prometheus
{{- end }}

{{/*
Loki labels
*/}}
{{- define "monitoring.loki.labels" -}}
{{ include "monitoring.labels" . }}
app.kubernetes.io/component: loki
{{- end }}

{{/*
Loki selector labels
*/}}
{{- define "monitoring.loki.selectorLabels" -}}
{{ include "monitoring.selectorLabels" . }}
app.kubernetes.io/component: loki
{{- end }}

{{/*
Tempo labels
*/}}
{{- define "monitoring.tempo.labels" -}}
{{ include "monitoring.labels" . }}
app.kubernetes.io/component: tempo
{{- end }}

{{/*
Tempo selector labels
*/}}
{{- define "monitoring.tempo.selectorLabels" -}}
{{ include "monitoring.selectorLabels" . }}
app.kubernetes.io/component: tempo
{{- end }}

{{/*
Grafana labels
*/}}
{{- define "monitoring.grafana.labels" -}}
{{ include "monitoring.labels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{/*
Grafana selector labels
*/}}
{{- define "monitoring.grafana.selectorLabels" -}}
{{ include "monitoring.selectorLabels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{/*
Kube State Metrics labels
*/}}
{{- define "monitoring.kubeStateMetrics.labels" -}}
{{ include "monitoring.labels" . }}
app.kubernetes.io/component: kube-state-metrics
{{- end }}

{{- define "monitoring.kubeStateMetrics.selectorLabels" -}}
{{ include "monitoring.selectorLabels" . }}
app.kubernetes.io/component: kube-state-metrics
{{- end }}

{{/*
Node Exporter labels
*/}}
{{- define "monitoring.nodeExporter.labels" -}}
{{ include "monitoring.labels" . }}
app.kubernetes.io/component: node-exporter
{{- end }}

{{- define "monitoring.nodeExporter.selectorLabels" -}}
{{ include "monitoring.selectorLabels" . }}
app.kubernetes.io/component: node-exporter
{{- end }}

{{/*
Redis Exporter labels
*/}}
{{- define "monitoring.redisExporter.labels" -}}
{{ include "monitoring.labels" . }}
app.kubernetes.io/component: redis-exporter
{{- end }}

{{- define "monitoring.redisExporter.selectorLabels" -}}
{{ include "monitoring.selectorLabels" . }}
app.kubernetes.io/component: redis-exporter
{{- end }}

{{/*
Create the name of the service account to use for Alloy
*/}}
{{- define "monitoring.alloy.serviceAccountName" -}}
{{- if .Values.alloy.rbac.create }}
{{- default "alloy" .Values.alloy.serviceAccountName }}
{{- else }}
{{- default "default" .Values.alloy.serviceAccountName }}
{{- end }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "monitoring.namespace" -}}
{{- default "monitoring" .Values.namespace }}
{{- end }}

