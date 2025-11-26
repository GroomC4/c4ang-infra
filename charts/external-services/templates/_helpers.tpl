{{/*
Expand the name of the chart.
*/}}
{{- define "external-services.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "external-services.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "external-services.labels" -}}
helm.sh/chart: {{ include "external-services.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.common.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Service labels
*/}}
{{- define "external-services.serviceLabels" -}}
{{ include "external-services.labels" . }}
app.kubernetes.io/part-of: external-services
{{- end }}
