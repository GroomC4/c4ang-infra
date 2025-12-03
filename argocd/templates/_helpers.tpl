{{/*
환경별 Target Revision 결정
사용법: {{ include "argocd.targetRevision" (dict "Values" .Values "env" "dev") }}
*/}}
{{- define "argocd.targetRevision" -}}
{{- $env := .env -}}
{{- $revision := .Values.global.targetRevision -}}
{{- if hasKey .Values.env $env -}}
  {{- $envConfig := index .Values.env $env -}}
  {{- if hasKey $envConfig "revision" -}}
    {{- $revision = index $envConfig "revision" -}}
  {{- end -}}
{{- end -}}
{{- $revision -}}
{{- end -}}
