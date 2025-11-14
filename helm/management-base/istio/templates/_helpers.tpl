{{/*
Expand the name of the chart.
*/}}
{{- define "istio.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "istio.fullname" -}}
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
{{- define "istio.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "istio.labels" -}}
helm.sh/chart: {{ include "istio.chart" . }}
{{ include "istio.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "istio.selectorLabels" -}}
app.kubernetes.io/name: {{ include "istio.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "istio.namespace" -}}
{{- default .Values.namespace.name .Values.namespace.override }}
{{- end }}

{{/*
Gateway name
*/}}
{{- define "istio.gateway.main.name" -}}
{{- default "ecommerce-gateway" .Values.gateway.main.name }}
{{- end }}

{{/*
Webhook Gateway name
*/}}
{{- define "istio.gateway.webhook.name" -}}
{{- default "webhook-gateway" .Values.gateway.webhook.name }}
{{- end }}

