{{/*
Expand the name of the chart.
*/}}
{{- define "sawmills-collector.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "sawmills-collector.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "sawmills-collector.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "sawmills-collector.labels" -}}
helm.sh/chart: {{ include "sawmills-collector.chart" . }}
{{ include "sawmills-collector.selectorLabels" . }}
{{- if .Values.image.tag }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sawmills-collector.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sawmills-collector.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "sawmills-collector.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default "sa-collector-service" .Values.serviceAccount.name }}
{{- else }}
{{- default "default" (default .Values.serviceAccountName .Values.serviceAccount.name ) }}
{{- end }}
{{- end }}

{{/*
Get the secret configuration, with backward compatibility support
Order of precedence:
1. New apiSecret configuration (recommended)
2. Existing prometheusremotewrite.api_key_secret (backward compatible)
3. Default values if none configured
*/}}
{{- define "sawmills-collector.secretConfig" -}}
{{- if .Values.apiSecret -}}
{{- with .Values.apiSecret -}}
name: {{ .name }}
key: {{ .key }}
{{- end -}}
{{- else if .Values.prometheusremotewrite.api_key_secret -}}
{{- with .Values.prometheusremotewrite.api_key_secret -}}
name: {{ .name }}
key: {{ .key }}
{{- end -}}
{{- else -}}
name: sawmills-secret
key: api-key
{{- end -}}
{{- end -}}  