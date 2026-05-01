{{/*
Expand the name of the chart.
*/}}
{{- define "sawmills-remote-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "sawmills-remote-operator.fullname" -}}
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
{{- define "sawmills-remote-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Build the remote-operator image reference. If image.digest is set, pin by digest and ignore image.tag.
*/}}
{{- define "sawmills-remote-operator.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- end -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "sawmills-remote-operator.labels" -}}
helm.sh/chart: {{ include "sawmills-remote-operator.chart" . }}
{{ include "sawmills-remote-operator.selectorLabels" . }}
{{- if .Values.image.tag }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "sawmills-remote-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sawmills-remote-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "sawmills-remote-operator.serviceAccountName" -}}
{{- $rbac := default dict .Values.rbac -}}
{{- if $rbac.createServiceAccount }}
{{- required "rbac.serviceAccountName must be set when rbac.createServiceAccount is true" $rbac.serviceAccountName }}
{{- else }}
{{- default "default" $rbac.serviceAccountName }}
{{- end }}
{{- end }}

{{/*
Static NO_PROXY entries that are always added when proxy.http or proxy.https is set.
*/}}
{{- define "sawmills-remote-operator.addNoProxy" -}}
localhost,127.0.0.1,::1,.cluster.local,.svc,.svc.cluster.local,kubernetes,kubernetes.default.svc,$(KUBERNETES_SERVICE_HOST),
{{- end }}

{{/*
Resolve NO_PROXY value. If proxy.http/https set, then append predefined values to user-defined noProxy.
Static values added here. Dynamic values (e.g. POD_IP) are appended in deployment.yaml.
*/}}
{{- define "sawmills-remote-operator.noProxyValue" -}}
{{- $proxy := default dict .Values.proxy -}}

{{- $userNoProxy := default (list) $proxy.noProxy -}}
{{- if kindIs "slice" $userNoProxy }}
  {{- $userNoProxy = join "," $userNoProxy -}}
{{- end -}}

{{- if not (or $proxy.http $proxy.https $proxy.existingSecret) }}
  {{- $userNoProxy -}}
{{- else }}
  {{- $addNoProxy := include "sawmills-remote-operator.addNoProxy" . -}}
  {{- $noProxy := list -}}
  {{- range splitList "," (printf "%s,%s" $addNoProxy $userNoProxy) }}
    {{- $noProxy = append $noProxy (trim .) -}}
  {{- end }}
  {{- join "," ($noProxy | compact | sortAlpha | uniq) -}}
{{- end }}
{{- end }}

{{/*
Fail fast if callers try to enable the embedded autoscaler in manual mode.
*/}}
{{- define "sawmills-remote-operator.failIfManualAutoscalerConfigured" -}}
{{- $autoscaler := default dict .Values.autoscaler -}}
{{- if or
    $autoscaler.enabled
    (ne $autoscaler.dryRun nil)
    $autoscaler.metricsEndpoint
    $autoscaler.otlpMetricsEndpoint
    $autoscaler.targetHPAName
    $autoscaler.leaseName
    (ne $autoscaler.labelSelectors nil)
    (ne $autoscaler.memoryLimitBytes nil)
    (ne $autoscaler.globalMinReplicas nil)
    (ne $autoscaler.globalMaxReplicas nil)
}}
{{- fail "autoscaler is not supported in sawmills-remote-operator-manual; manual deployments must manage scaling outside the remote operator" }}
{{- end }}
{{- end }}
