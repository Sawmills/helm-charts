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
Common labels
*/}}
{{- define "sawmills-collector.loadBalancerLabels" -}}
helm.sh/chart: {{ include "sawmills-collector.chart" . }}
{{ include "sawmills-collector.loadBalancerSelectorLabels" . }}
{{- if .Values.image.tag }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sawmills-collector.loadBalancerSelectorLabels" -}}
app.kubernetes.io/name: {{ include "sawmills-collector.name" . }}-lb
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

{{/*
Generate external labels transform processor configuration
*/}}
{{- define "sawmills-collector.externalLabelsProcessor" -}}
{{- $hasLabels := false -}}
{{- if .Values.prometheusremotewrite -}}
  {{- if .Values.prometheusremotewrite.external_labels -}}
    {{- $hasLabels = true -}}
  {{- end -}}
{{- end -}}
{{- if $hasLabels -}}
error_mode: ignore
metric_statements:
- context: datapoint
  statements:
  {{- range $key, $value := .Values.prometheusremotewrite.external_labels }}
  - set(attributes["{{ $key }}"], "{{ $value }}") where attributes["{{ $key }}"] == nil
  {{- end }}
{{- else -}}
error_mode: ignore
metric_statements: []
{{- end -}}
{{- end -}}

{{/*
Generate merged telemetry configuration with external labels
*/}}
{{- define "sawmills-collector.telemetryConfig" -}}
{{- if .Values.telemetryConfig }}
{{- $config := .Values.telemetryConfig }}
{{- if and .Values.haproxy.enabled (not .Values.loadBalancer.enabled) }}
  {{- $config = merge $config .Values.haproxyConfig }}
{{- end }}
{{- if .Values.kedaScaler.enabled }}
  {{- $config = merge $config .Values.kedaScaler.telemetryConfig }}
{{- end }}
{{- if eq .Values.telemetryExternalConfig.type "prometheus" }}
  {{- $config = merge $config .Values.telemetryExternalConfig.prometheusConfig }}
{{- else if eq .Values.telemetryExternalConfig.type "arrow" }}
  {{- $config = merge $config .Values.telemetryExternalConfig.arrowConfig }}
{{- end }}
{{- /* Override transform/external_labels processor with dynamic config */ -}}
{{- if and (hasKey $config "processors") (hasKey $config.processors "transform/external_labels") .Values.prometheusremotewrite .Values.prometheusremotewrite.external_labels }}
  {{- $processor := include "sawmills-collector.externalLabelsProcessor" . | fromYaml }}
  {{- $_ := set $config.processors "transform/external_labels" $processor }}
{{- end }}
{{- toYaml $config }}
{{- end }}
{{- end -}}

{{/*
Generate merged telemetry configuration with external labels
*/}}
{{- define "sawmills-collector.loadBalancerTelemetryConfig" -}}
{{- if .Values.telemetryConfig }}
{{- $config := .Values.telemetryConfig }}
{{- if .Values.haproxy.enabled }}
  {{- $config = merge $config .Values.haproxyConfig }}
{{- end }}
{{- if .Values.kedaScaler.enabled }}
  {{- $config = merge $config .Values.kedaScaler.telemetryConfig }}
{{- end }}
{{- if eq .Values.telemetryExternalConfig.type "prometheus" }}
  {{- $config = merge $config .Values.telemetryExternalConfig.prometheusConfig }}
{{- else if eq .Values.telemetryExternalConfig.type "arrow" }}
  {{- $config = merge $config .Values.telemetryExternalConfig.arrowConfig }}
{{- end }}
{{- /* Override transform/external_labels processor with dynamic config */ -}}
{{- if and (hasKey $config "processors") (hasKey $config.processors "transform/external_labels") .Values.prometheusremotewrite .Values.prometheusremotewrite.external_labels }}
  {{- $processor := include "sawmills-collector.externalLabelsProcessor" . | fromYaml }}
  {{- $_ := set $config.processors "transform/external_labels" $processor }}
{{- end }}
{{- toYaml $config }}
{{- end }}
{{- end -}}

{{/*
Static NO_PROXY entries that are always added when proxy.http or proxy.https is set.
*/}}
{{- define "sawmills-collector.addNoProxy" -}}
localhost,127.0.0.1,::1,.cluster.local,.svc,.svc.cluster.local,kubernetes,kubernetes.default.svc,$(KUBERNETES_SERVICE_HOST),
{{- end }}

{{/*
Resolve NO_PROXY value. If proxy.http/https set, then append predefined values to user-defined noProxy.
*/}}
{{- define "sawmills-collector.noProxyValue" -}}
{{- $proxy := default dict .Values.proxy -}}

{{- $userNoProxy := default (list) $proxy.noProxy -}}
{{- if kindIs "slice" $userNoProxy }}
  {{- $userNoProxy = join "," $userNoProxy -}}
{{- end -}}

{{- if not (or $proxy.http $proxy.https) }}
  {{- $userNoProxy -}}
{{- else }}
  {{- $addNoProxy := include "sawmills-collector.addNoProxy" . -}}
  {{- $noProxy := list -}}
  {{- range splitList "," (printf "%s,%s" $addNoProxy $userNoProxy) }}
    {{- $noProxy = append $noProxy (trim .) -}}
  {{- end }}
  {{- join "," ($noProxy | compact | sortAlpha | uniq) -}}
{{- end }}
{{- end }}

{{/*
Generate complete proxy environment with ALL(!) variables (HTTP_PROXY, HTTPS_PROXY, NO_PROXY).
Populate NO_PRQOXY with both static and dymanic (e.g. MY_POD_IP) values
*/}}
{{- define "sawmills-collector.proxyEnv" -}}
{{- $proxy := default dict .Values.proxy }}
{{- with $proxy.http }}
- name: HTTP_PROXY
  value: {{ tpl . $ | quote }}
{{- end }}
{{- with $proxy.https }}
- name: HTTPS_PROXY
  value: {{ tpl . $ | quote }}
{{- end }}
{{- $noProxy := include "sawmills-collector.noProxyValue" . }}
{{- if or $proxy.http $proxy.https $noProxy }}
- name: NO_PROXY
  {{- if or $proxy.http $proxy.https }}
    {{- if $noProxy }}
  value: {{ printf "%s,$(MY_POD_IP)" $noProxy | quote }}
    {{- else }}
  value: "$(MY_POD_IP)"
    {{- end }}
  {{- else }}
  value: {{ $noProxy | quote }}
  {{- end }}
{{- end }}
{{- end }}
