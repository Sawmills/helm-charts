{{/*
Expand the name of the chart.
*/}}
{{- define "sawmills-collector.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Resolve the runtime resource base name.
Defaults to the Helm release name for backward compatibility.
*/}}
{{- define "sawmills-collector.resourceBaseName" -}}
{{- default .Release.Name .Values.resourceBaseName | toString | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Returns the runtime resource base name: .Values.resourceBaseName when set,
otherwise .Release.Name for backward compatibility.
*/}}
{{- define "sawmills-collector.fullname" -}}
{{- include "sawmills-collector.resourceBaseName" . }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "sawmills-collector.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Build the collector image reference. If image.digest is set, pin by digest and ignore image.tag.
*/}}
{{- define "sawmills-collector.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (default "dev" .Values.image.tag) -}}
{{- end -}}
{{- end }}

{{/*
Name backend drain config by collector image so old ReplicaSets never consume
config rendered for a newer binary that may contain unsupported extensions.
*/}}
{{- define "sawmills-collector.backendDrainConfigName" -}}
{{- $imageHash := include "sawmills-collector.image" . | sha256sum | trunc 12 -}}
{{- printf "%s-backend-drain-config-%s" (include "sawmills-collector.fullname" .) $imageHash | trunc 253 | trimSuffix "-" -}}
{{- end }}

{{/*
Build the HAProxy image reference. Supports the legacy haproxy.image string and
the structured haproxy.image.repository/tag/digest format.
*/}}
{{- define "sawmills-collector.haproxyImage" -}}
{{- $image := .Values.haproxy.image -}}
{{- if kindIs "map" $image -}}
{{- $repository := default "public.ecr.aws/docker/library/haproxy" $image.repository -}}
{{- if $image.digest -}}
{{- printf "%s@%s" $repository $image.digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (default "3.1.15" $image.tag) -}}
{{- end -}}
{{- else -}}
{{- $image -}}
{{- end -}}
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
{{- define "sawmills-collector.selectorName" -}}
{{- if .Values.resourceBaseName -}}
{{- include "sawmills-collector.resourceBaseName" . }}
{{- else -}}
{{- include "sawmills-collector.name" . }}
{{- end }}
{{- end }}

{{- define "sawmills-collector.selectorInstance" -}}
{{- .Release.Name }}
{{- end }}

{{- define "sawmills-collector.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sawmills-collector.selectorName" . }}
app.kubernetes.io/instance: {{ include "sawmills-collector.selectorInstance" . }}
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
{{- define "sawmills-collector.loadBalancerSelectorName" -}}
{{- if .Values.resourceBaseName -}}
{{- printf "%s-lb" (include "sawmills-collector.resourceBaseName" .) | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{- printf "%s-lb" (include "sawmills-collector.name" .) }}
{{- end }}
{{- end }}

{{- define "sawmills-collector.loadBalancerSelectorLabels" -}}
app.kubernetes.io/name: {{ include "sawmills-collector.loadBalancerSelectorName" . }}
app.kubernetes.io/instance: {{ include "sawmills-collector.selectorInstance" . }}
{{- end }}

{{/*
Render affinity values while preserving backward-compatible defaults.
When resourceBaseName is set, only the chart's built-in legacy selector name is rewritten.
*/}}
{{- define "sawmills-collector.renderAffinity" -}}
{{- $root := index . "root" -}}
{{- $affinity := toYaml (index . "affinity") -}}
{{- if $root.Values.resourceBaseName -}}
{{- $legacyListItem := printf "- %s" (index . "legacyName") -}}
{{- $selectorListItem := printf "- %s" (index . "selectorName") -}}
{{- $affinity = replace $legacyListItem $selectorListItem $affinity -}}
{{- end -}}
{{- $affinity -}}
{{- end }}

{{- define "sawmills-collector.renderCollectorAffinity" -}}
{{- include "sawmills-collector.renderAffinity" (dict "root" . "affinity" .Values.affinity "legacyName" "sawmills-collector-chart" "selectorName" (include "sawmills-collector.selectorName" .)) -}}
{{- end }}

{{- define "sawmills-collector.renderLoadBalancerAffinity" -}}
{{- include "sawmills-collector.renderAffinity" (dict "root" . "affinity" .Values.loadBalancer.affinity "legacyName" "sawmills-collector-chart-lb" "selectorName" (include "sawmills-collector.loadBalancerSelectorName" .)) -}}
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
Resolve the runtime folder name injected as FOLDER_NAME.
collectorConfig.folderName is the clear public value; quotamgmtprocessor.folder_name
is kept as a backward-compatible alias for reused release values.
*/}}
{{- define "sawmills-collector.folderName" -}}
{{- $collectorConfig := default dict .Values.collectorConfig -}}
{{- $folderName := "" -}}
{{- if and (kindIs "map" $collectorConfig) (hasKey $collectorConfig "folderName") -}}
{{- $folderName = (default "" (get $collectorConfig "folderName") | toString) -}}
{{- end -}}
{{- if $folderName -}}
{{- $folderName -}}
{{- else -}}
{{- $qmp := default dict .Values.quotamgmtprocessor -}}
{{- default "SAWMILLS_ORG" $qmp.folder_name -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the runtime S3 bucket injected as S3_BUCKET.
collectorConfig.s3Bucket is the clear public value; quotamgmtprocessor.s3_bucket
is kept as a backward-compatible alias for reused release values.
*/}}
{{- define "sawmills-collector.s3Bucket" -}}
{{- $collectorConfig := default dict .Values.collectorConfig -}}
{{- $s3Bucket := "" -}}
{{- if and (kindIs "map" $collectorConfig) (hasKey $collectorConfig "s3Bucket") -}}
{{- $s3Bucket = (default "" (get $collectorConfig "s3Bucket") | toString) -}}
{{- end -}}
{{- if $s3Bucket -}}
{{- $s3Bucket -}}
{{- else -}}
{{- $qmp := default dict .Values.quotamgmtprocessor -}}
{{- default "sawmills-plat-ue1-prod-quotas" $qmp.s3_bucket -}}
{{- end -}}
{{- end -}}

{{/*
Common runtime environment used by collector containers that load remote
pipeline configs referencing ${env:FOLDER_NAME} and ${env:S3_BUCKET}.
*/}}
{{- define "sawmills-collector.runtimeConfigEnv" -}}
- name: MY_POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: MY_POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: FOLDER_NAME
  value: {{ include "sawmills-collector.folderName" . | quote }}
- name: S3_BUCKET
  value: {{ include "sawmills-collector.s3Bucket" . | quote }}
- name: COLLECTOR_NAME
  value: {{ .Values.collectorName | quote }}
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
Add configured external labels directly to the prometheusremotewrite exporter.
This avoids datapoint-level transform work on the Prometheus remote write path.
Mutates the passed config in place and emits no YAML output.
*/}}
{{- define "sawmills-collector.applyPrometheusRemoteWriteExternalLabels" -}}
{{- $root := .root -}}
{{- $config := .config -}}
{{- $labels := $root.Values.prometheusremotewrite.external_labels | default dict -}}
{{- if and $config (not (empty $labels)) -}}
  {{- $exporters := get $config "exporters" | default dict -}}
  {{- $promRW := get $exporters "prometheusremotewrite" | default dict -}}
  {{- $existingExternalLabels := get $promRW "external_labels" | default dict -}}
  {{- $_ := set $promRW "external_labels" (mergeOverwrite (deepCopy $existingExternalLabels) (deepCopy $labels)) -}}
  {{- $_ := set $exporters "prometheusremotewrite" $promRW -}}
  {{- $_ := set $config "exporters" $exporters -}}
{{- end -}}
{{- end -}}

{{/*
Remove the legacy transform-only external-label processor from the Prometheus
remote write pipeline. If custom processors are configured beside the
transform, preserve the explicit chain because those processors may depend on
the attributes the transform adds before export.
*/}}
{{- define "sawmills-collector.removePrometheusRemoteWriteExternalLabelProcessor" -}}
{{- $config := .config -}}
{{- if $config -}}
  {{- $service := get $config "service" | default dict -}}
  {{- $pipelines := get $service "pipelines" | default dict -}}
  {{- $promRWPipeline := get $pipelines "metrics/external/prometheusremotewrite" | default dict -}}
  {{- if hasKey $promRWPipeline "processors" -}}
    {{- $hasExternalLabelProcessor := false -}}
    {{- $keptProcessors := list -}}
    {{- range $processor := (get $promRWPipeline "processors" | default list) -}}
      {{- if ne (toString $processor) "transform/external_labels" -}}
        {{- $keptProcessors = append $keptProcessors $processor -}}
      {{- else -}}
        {{- $hasExternalLabelProcessor = true -}}
      {{- end -}}
    {{- end -}}
    {{- if and $hasExternalLabelProcessor (empty $keptProcessors) -}}
      {{- $_ := unset $promRWPipeline "processors" -}}
      {{- $_ := set $pipelines "metrics/external/prometheusremotewrite" $promRWPipeline -}}
      {{- $_ := set $service "pipelines" $pipelines -}}
      {{- $_ := set $config "service" $service -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return true when any configured telemetry pipeline still references the legacy
external-label transform. This keeps the default Prometheus remote write path
exporter-native while preserving custom and Arrow pipelines that use the
processor contract directly.
*/}}
{{- define "sawmills-collector.usesExternalLabelProcessor" -}}
{{- $config := .config -}}
{{- $usesExternalLabelProcessor := false -}}
{{- if $config -}}
  {{- $service := get $config "service" | default dict -}}
  {{- $pipelines := get $service "pipelines" | default dict -}}
  {{- range $_, $pipeline := $pipelines -}}
    {{- range $processor := (get $pipeline "processors" | default list) -}}
      {{- if eq (toString $processor) "transform/external_labels" -}}
        {{- $usesExternalLabelProcessor = true -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if $usesExternalLabelProcessor }}true{{ else }}false{{ end -}}
{{- end -}}

{{/*
Generate merged telemetry configuration with external labels
*/}}
{{- define "sawmills-collector.telemetryConfig" -}}
{{- if .Values.telemetryConfig }}
{{- $config := deepCopy .Values.telemetryConfig }}
{{- if and .Values.haproxy.enabled (not .Values.loadBalancer.enabled) }}
  {{- $config = merge $config .Values.haproxyConfig }}
{{- end }}
{{- if eq .Values.telemetryExternalConfig.type "prometheus" }}
  {{- $config = merge $config .Values.telemetryExternalConfig.prometheusConfig }}
  {{- include "sawmills-collector.applyPrometheusRemoteWriteExternalLabels" (dict "root" . "config" $config) }}
  {{- include "sawmills-collector.removePrometheusRemoteWriteExternalLabelProcessor" (dict "config" $config) }}
{{- else if eq .Values.telemetryExternalConfig.type "arrow" }}
  {{- $config = merge $config .Values.telemetryExternalConfig.arrowConfig }}
{{- end }}
{{- if and (eq (include "sawmills-collector.usesExternalLabelProcessor" (dict "config" $config)) "true") (hasKey $config "processors") (hasKey $config.processors "transform/external_labels") .Values.prometheusremotewrite .Values.prometheusremotewrite.external_labels }}
  {{- $processor := include "sawmills-collector.externalLabelsProcessor" . | fromYaml }}
  {{- $_ := set $config.processors "transform/external_labels" $processor }}
{{- end }}
{{- include "sawmills-collector.addTelemetryPprof" (dict "root" . "config" $config) }}
{{- toYaml $config }}
{{- end }}
{{- end -}}

{{/*
Validate telemetry-sidecar pprof config source and pod-local port safety.
Emits no output; calls fail when configuration would expose or break pprof.
*/}}
{{- define "sawmills-collector.validateTelemetryPprof" -}}
{{- $pprof := .Values.telemetry.pprof | default dict -}}
{{- if ($pprof.enabled | default false) }}
  {{- $configSource := default "chart" $pprof.configSource -}}
  {{- if not (has $configSource (list "chart" "external")) }}
    {{- fail (printf "telemetry.pprof.configSource must be one of: chart, external (got %q)" $configSource) }}
  {{- end }}
  {{- $pprofPortValue := 1778 -}}
  {{- if hasKey $pprof "port" }}
    {{- $pprofPortValue = $pprof.port -}}
  {{- end }}
  {{- if not (regexMatch "^[0-9]+$" (toString $pprofPortValue)) }}
    {{- fail (printf "telemetry.pprof.port must be an integer between 1 and 65535 (got %q)" (toString $pprofPortValue)) }}
  {{- end }}
  {{- $pprofPort := int $pprofPortValue -}}
  {{- if or (lt $pprofPort 1) (gt $pprofPort 65535) }}
    {{- fail (printf "telemetry.pprof.port must be between 1 and 65535 (got %d)" $pprofPort) }}
  {{- end }}
  {{- $telemetryPrometheusPort := int (default 19465 .Values.telemetry.prometheus.port) -}}
  {{- if eq $pprofPort $telemetryPrometheusPort }}
    {{- fail (printf "telemetry.pprof.port %d conflicts with telemetry.prometheus.port" $pprofPort) }}
  {{- end }}
  {{- if eq $pprofPort 13133 }}
    {{- fail (printf "telemetry.pprof.port %d conflicts with main collector health_check port 13133" $pprofPort) }}
  {{- end }}
  {{- if eq $pprofPort 13134 }}
    {{- fail (printf "telemetry.pprof.port %d conflicts with telemetry collector health_check port 13134" $pprofPort) }}
  {{- end }}
  {{- if eq $pprofPort 1777 }}
    {{- fail (printf "telemetry.pprof.port %d conflicts with main collector pprof port 1777" $pprofPort) }}
  {{- end }}
  {{- if eq $pprofPort 13138 }}
    {{- fail (printf "telemetry.pprof.port %d conflicts with main collector LiveTail control port 13138" $pprofPort) }}
  {{- end }}
  {{- range $name, $portConfig := (.Values.ports | default dict) }}
    {{- $port := int (default 0 $portConfig.port) -}}
    {{- if and (gt $port 0) (eq $pprofPort $port) }}
      {{- fail (printf "telemetry.pprof.port %d conflicts with ports.%s.port" $pprofPort $name) }}
    {{- end }}
  {{- end }}
  {{- range $name, $servicePort := (.Values.service.ports | default dict) }}
    {{- $targetPortValue := default 0 $servicePort.from -}}
    {{- if eq (toString $targetPortValue) "telemetry-pprof" }}
      {{- fail (printf "telemetry.pprof.port %d conflicts with service.ports.%s.from targetPort telemetry-pprof" $pprofPort $name) }}
    {{- end }}
    {{- $targetPort := int $targetPortValue -}}
    {{- if and (regexMatch "^[0-9]+$" (toString $targetPortValue)) (gt $targetPort 0) (eq $pprofPort $targetPort) }}
      {{- fail (printf "telemetry.pprof.port %d conflicts with service.ports.%s.from" $pprofPort $name) }}
    {{- end }}
  {{- end }}
  {{- $mainDrain := .Values.rollout.main.drain | default dict -}}
  {{- if and .Values.loadBalancer.enabled ($mainDrain.enabled | default false) }}
    {{- $mainDrainPort := int (default 13137 $mainDrain.port) -}}
    {{- if eq $pprofPort $mainDrainPort }}
      {{- fail (printf "telemetry.pprof.port %d conflicts with rollout.main.drain.port" $pprofPort) }}
    {{- end }}
  {{- end }}
  {{- if .Values.haproxy.enabled }}
    {{- range $name, $mapping := (.Values.haproxy.mapping | default dict) }}
      {{- $port := int (default 0 $mapping.from) -}}
      {{- if and (gt $port 0) (eq $pprofPort $port) }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with haproxy.mapping.%s.from" $pprofPort $name) }}
      {{- end }}
      {{- $to := $mapping.to | default dict -}}
      {{- $targetPort := int (default 0 $to.port) -}}
      {{- if and (gt $targetPort 0) (eq $pprofPort $targetPort) }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with haproxy.mapping.%s.to.port" $pprofPort $name) }}
      {{- end }}
    {{- end }}
    {{- $siblingFallback := .Values.haproxy.sibling_fallback | default dict -}}
    {{- if ($siblingFallback.enabled | default false) }}
      {{- $siblingCheck := $siblingFallback.check | default dict -}}
      {{- $siblingCheckPort := int (default 13136 $siblingCheck.port) -}}
      {{- if eq $pprofPort $siblingCheckPort }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with haproxy.sibling_fallback.check.port" $pprofPort) }}
      {{- end }}
    {{- end }}
    {{- if (.Values.haproxy.prometheus.enabled | default false) }}
      {{- $haproxyPrometheusPort := int (default 8405 .Values.haproxy.prometheus.port) -}}
      {{- if eq $pprofPort $haproxyPrometheusPort }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with haproxy.prometheus.port" $pprofPort) }}
      {{- end }}
    {{- end }}
    {{- if (.Values.haproxy.stats.enabled | default false) }}
      {{- $haproxyStatsPort := int (default 8406 .Values.haproxy.stats.port) -}}
      {{- if eq $pprofPort $haproxyStatsPort }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with haproxy.stats.port" $pprofPort) }}
      {{- end }}
    {{- end }}
    {{- if (.Values.haproxy.healthcheck.enabled | default false) }}
      {{- $haproxyHealthPort := int (default 13135 .Values.haproxy.healthcheck.port) -}}
      {{- if eq $pprofPort $haproxyHealthPort }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with haproxy.healthcheck.port" $pprofPort) }}
      {{- end }}
      {{- $forwardingHealth := .Values.haproxy.healthcheck.forwarding_health | default dict -}}
      {{- if ($forwardingHealth.enabled | default false) }}
        {{- $forwardingHealthPort := int (default 13136 $forwardingHealth.port) -}}
        {{- if eq $pprofPort $forwardingHealthPort }}
          {{- fail (printf "telemetry.pprof.port %d conflicts with haproxy.healthcheck.forwarding_health.port" $pprofPort) }}
        {{- end }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- if .Values.loadBalancer.enabled }}
    {{- range $name, $portConfig := (.Values.loadBalancer.ports | default dict) }}
      {{- $port := int (default 0 $portConfig.port) -}}
      {{- if and (gt $port 0) (eq $pprofPort $port) }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with loadBalancer.ports.%s.port" $pprofPort $name) }}
      {{- end }}
    {{- end }}
    {{- range $name, $servicePort := (.Values.loadBalancer.service.ports | default dict) }}
      {{- $targetPortValue := default 0 $servicePort.from -}}
      {{- if eq (toString $targetPortValue) "telemetry-pprof" }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with loadBalancer.service.ports.%s.from targetPort telemetry-pprof" $pprofPort $name) }}
      {{- end }}
      {{- $targetPort := int $targetPortValue -}}
      {{- if and (regexMatch "^[0-9]+$" (toString $targetPortValue)) (gt $targetPort 0) (eq $pprofPort $targetPort) }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with loadBalancer.service.ports.%s.from" $pprofPort $name) }}
      {{- end }}
    {{- end }}
    {{- $remoteOperatorPort := int (default 14319 .Values.telemetry.remoteOperatorOtlpHttpPort) -}}
    {{- if eq $pprofPort $remoteOperatorPort }}
      {{- fail (printf "telemetry.pprof.port %d conflicts with telemetry.remoteOperatorOtlpHttpPort" $pprofPort) }}
    {{- end }}
    {{- $lbPressure := .Values.loadBalancer.pressureReadiness | default dict -}}
    {{- if ($lbPressure.enabled | default false) }}
      {{- $pressurePrometheusPort := int (default 19466 .Values.telemetry.pressurePrometheus.port) -}}
      {{- if eq $pprofPort $pressurePrometheusPort }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with telemetry.pressurePrometheus.port" $pprofPort) }}
      {{- end }}
      {{- $pressureReadinessPort := int (default 13137 $lbPressure.port) -}}
      {{- if eq $pprofPort $pressureReadinessPort }}
        {{- fail (printf "telemetry.pprof.port %d conflicts with loadBalancer.pressureReadiness.port" $pprofPort) }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- $telemetryOtelConfig := default dict .Values.telemetryOtelConfig -}}
  {{- $lbTelemetryOtelConfig := default dict .Values.loadBalancer.telemetryOtelConfig -}}
  {{- $telemetryS3Path := default "" $telemetryOtelConfig.s3path -}}
  {{- $lbTelemetryS3Path := default "" $lbTelemetryOtelConfig.s3path -}}
  {{- if and (eq $configSource "chart") (or $telemetryS3Path (and .Values.loadBalancer.enabled $lbTelemetryS3Path)) }}
    {{- fail "telemetry.pprof.configSource must be external when telemetry pprof is enabled with S3-backed telemetry config; ensure the S3 telemetry config contains the pprof extension" }}
  {{- end }}
  {{- if and (eq $configSource "external") (not $telemetryS3Path) }}
    {{- fail "telemetry.pprof.configSource=external requires telemetryOtelConfig.s3path because Helm will not inject pprof into inline telemetry config" }}
  {{- end }}
  {{- if and (eq $configSource "external") .Values.loadBalancer.enabled (not $lbTelemetryS3Path) }}
    {{- fail "telemetry.pprof.configSource=external requires loadBalancer.telemetryOtelConfig.s3path when loadBalancer.enabled=true because Helm will not inject pprof into inline LB telemetry config" }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Add pprof to a telemetry-sidecar collector config when telemetry.pprof.enabled=true.
The sidecar uses TELEMETRY_PPROF_PORT so it never collides with main collector pprof.
Mutates the passed config in place and emits no YAML output.
*/}}
{{- define "sawmills-collector.addTelemetryPprof" -}}
{{- $root := .root -}}
{{- $config := .config -}}
{{- $pprofValues := $root.Values.telemetry.pprof | default dict -}}
{{- if and $config (($pprofValues.enabled | default false)) (eq (default "chart" $pprofValues.configSource) "chart") }}
  {{- $extensions := get $config "extensions" | default dict }}
  {{- $pprof := get $extensions "pprof" | default dict }}
  {{- $_ := set $pprof "endpoint" "0.0.0.0:${env:TELEMETRY_PPROF_PORT}" }}
  {{- $_ := set $extensions "pprof" $pprof }}
  {{- $_ := set $config "extensions" $extensions }}
  {{- $service := get $config "service" | default dict }}
  {{- $serviceExtensions := get $service "extensions" | default list }}
  {{- if not (has "pprof" $serviceExtensions) }}
    {{- $serviceExtensions = append $serviceExtensions "pprof" }}
  {{- end }}
  {{- $_ := set $service "extensions" $serviceExtensions }}
  {{- $_ := set $config "service" $service }}
{{- end }}
{{- end -}}

{{/*
Generate merged telemetry configuration with external labels
*/}}
{{- define "sawmills-collector.loadBalancerTelemetryConfig" -}}
{{- $baseTelemetryConfig := .Values.telemetryConfig }}
{{- $hasSharedTelemetryBase := not (empty .Values.telemetryConfig) }}
{{- if .Values.loadBalancer.telemetryConfig }}
  {{- if $hasSharedTelemetryBase }}
    {{- $baseTelemetryConfig = mergeOverwrite (deepCopy .Values.telemetryConfig) .Values.loadBalancer.telemetryConfig }}
  {{- else }}
    {{- $baseTelemetryConfig = deepCopy .Values.loadBalancer.telemetryConfig }}
  {{- end }}
{{- end }}
{{- if $baseTelemetryConfig }}
{{- $config := deepCopy $baseTelemetryConfig }}
{{- if and $hasSharedTelemetryBase .Values.haproxy.enabled }}
  {{- $config = merge $config .Values.haproxyConfig }}
{{- end }}
{{- if and $hasSharedTelemetryBase (eq .Values.telemetryExternalConfig.type "prometheus") }}
  {{- $config = merge $config .Values.telemetryExternalConfig.prometheusConfig }}
  {{- include "sawmills-collector.applyPrometheusRemoteWriteExternalLabels" (dict "root" . "config" $config) }}
  {{- include "sawmills-collector.removePrometheusRemoteWriteExternalLabelProcessor" (dict "config" $config) }}
{{- else if and $hasSharedTelemetryBase (eq .Values.telemetryExternalConfig.type "arrow") }}
  {{- $config = merge $config .Values.telemetryExternalConfig.arrowConfig }}
{{- end }}
{{- if $hasSharedTelemetryBase }}
{{- if eq .Values.telemetryExternalConfig.type "prometheus" }}
  {{- $lbTelemetryOverride := .Values.loadBalancer.telemetryConfig | default dict }}
  {{- $lbOverrideService := get $lbTelemetryOverride "service" | default dict }}
  {{- $lbOverridePipelines := get $lbOverrideService "pipelines" | default dict }}
  {{- $lbOverrideExporters := get $lbTelemetryOverride "exporters" | default dict }}
  {{- $hasExplicitLBPromRWOverride := or (hasKey $lbOverridePipelines "metrics/external/prometheusremotewrite") (hasKey $lbOverrideExporters "prometheusremotewrite") }}
  {{- $service := get $config "service" | default dict }}
  {{- $pipelines := get $service "pipelines" | default dict }}
  {{- if and (not $hasExplicitLBPromRWOverride) (hasKey $pipelines "metrics/external/prometheusremotewrite") }}
  {{- $processors := get $config "processors" | default dict }}
  {{- $_ := set $processors "filter/lb_remote_write" (dict "error_mode" "ignore" "metrics" (dict "metric" (list "not IsMatch(name, \"^(otelcol_loadbalancer_central_queue_(compressed_bytes|compressed_capacity|compressed_capacity_bytes|saturation|items|rejected_compressed_bytes(_total)?|retries|decode_failures|inflight_uncompressed_bytes|inflight_uncompressed_capacity|inflight_uncompressed_capacity_bytes|configured_consumers|active_load_balancer_replicas|effective_consumers|active_consumers|queue_demand_consumers|backend_safe_consumers_per_lb|consumer_limit_reason|consumer_pressure_state|lanes|effective_lanes|oldest_item_age(_milliseconds)?|ready_windows|ready_window_limit|ready_lanes|ready_uncompressed_bytes|scheduler_state)|otelcol_loadbalancer_backend_(latency.*|outcome.*|quarantine_total|unquarantine_total|fail_open_total|reroute_total|stale_total)|otelcol_loadbalancer_num_(backends|backend_updates|resolutions)|otelcol_loadbalancer_resolver_stale_age|otelcol_(receiver|processor)_(accepted|refused)_(log_records|metric_points|spans)(_total)?|otelcol_exporter_queue_(size|capacity|oldest_batch_age)|otelcol_process_(cpu_seconds(_total)?|memory_rss(_bytes)?|runtime_heap_alloc_bytes)|process_(cpu_seconds_total|resident_memory_bytes)|haproxy_frontend_(http_requests_total|current_sessions|sessions_total|connections_total|bytes_in_total)|haproxy_backend_(http_requests_total|http_responses_total|loadbalanced_total|current_sessions|sessions_total|bytes_in_total|active_servers|backup_servers|current_queue)|haproxy_server_(http_responses_total|current_sessions|sessions_total|bytes_in_total|connection_errors_total|check_up_down_total|status)|http\\\\.server\\\\.(duration|request\\\\.duration).*)$\")"))) }}
  {{- $_ := set $config "processors" $processors }}
  {{- $exporters := get $config "exporters" | default dict }}
  {{- $promRW := get $exporters "prometheusremotewrite" | default dict }}
  {{- $_ := set $promRW "timeout" "30s" }}
  {{- $existingExternalLabels := get $promRW "external_labels" | default dict }}
  {{- $_ := set $promRW "external_labels" (mergeOverwrite (deepCopy $existingExternalLabels) (deepCopy (.Values.prometheusremotewrite.external_labels | default dict))) }}
  {{- $_ := set $promRW "max_batch_request_parallelism" 1 }}
  {{- $_ := set $promRW "max_batch_size_bytes" 6000000 }}
  {{- $remoteWriteQueue := get $promRW "remote_write_queue" | default dict }}
  {{- $_ := set $remoteWriteQueue "enabled" true }}
  {{- $_ := set $remoteWriteQueue "queue_size" 500 }}
  {{- $_ := set $remoteWriteQueue "num_consumers" 4 }}
  {{- $_ := set $promRW "remote_write_queue" $remoteWriteQueue }}
  {{- $_ := set $exporters "prometheusremotewrite" $promRW }}
  {{- $_ := set $config "exporters" $exporters }}
  {{- $externalPromRW := get $pipelines "metrics/external/prometheusremotewrite" | default dict }}
  {{- $currentProcessors := get $externalPromRW "processors" | default list }}
  {{- $hasExternalLabelProcessor := false }}
  {{- $customProcessors := list }}
  {{- range $processor := $currentProcessors }}
    {{- $processorName := toString $processor }}
    {{- if eq $processorName "transform/external_labels" }}
      {{- $hasExternalLabelProcessor = true }}
    {{- else if ne $processorName "filter/lb_remote_write" }}
      {{- $customProcessors = append $customProcessors $processor }}
    {{- end }}
  {{- end }}
  {{- $slimProcessors := list "filter/lb_remote_write" }}
  {{- if and $hasExternalLabelProcessor (not (empty $customProcessors)) }}
    {{- $slimProcessors = append $slimProcessors "transform/external_labels" }}
  {{- end }}
  {{- range $processor := $customProcessors }}
    {{- $slimProcessors = append $slimProcessors $processor }}
  {{- end }}
  {{- $_ := set $externalPromRW "processors" $slimProcessors }}
  {{- $_ := set $pipelines "metrics/external/prometheusremotewrite" $externalPromRW }}
  {{- $_ := set $service "pipelines" $pipelines }}
  {{- $_ := set $config "service" $service }}
  {{- end }}
{{- end }}
{{- /* LB-only remote-operator OTLP ingest wiring (receiver + dedicated pipeline). */ -}}
{{- $lbOverlay := (fromYaml (printf "receivers:\n  otlp/remote_operator:\n    protocols:\n      http:\n        endpoint: ${env:MY_POD_IP}:%v\nprocessors:\n  transform/remove_unit_preserve_service_name:\n    error_mode: ignore\n    metric_statements:\n      - context: metric\n        statements:\n          - set(metric.unit, \"\")\nservice:\n  pipelines:\n    metrics/remote_operator:\n      receivers:\n        - otlp/remote_operator\n      processors:\n        - memory_limiter\n        - transform/remove_unit_preserve_service_name\n        - deltatocumulative\n        - batch\n      exporters:\n        - routing\n        - forward\n" (.Values.telemetry.remoteOperatorOtlpHttpPort | default 14319))) }}
{{- $config = merge $config $lbOverlay }}
{{- $lbPressureReadiness := .Values.loadBalancer.pressureReadiness | default dict }}
{{- if ($lbPressureReadiness.enabled | default false) }}
  {{- $pressurePrometheusEndpoint := printf "${env:MY_POD_IP}:%v" (.Values.telemetry.pressurePrometheus.port | default 19466) }}
  {{- $pressureOverlay := (fromYaml (printf "exporters:\n  prometheus/pressure_readiness:\n    endpoint: %s\n    metric_expiration: 1m\nprocessors:\n  filter/pressure_readiness:\n    error_mode: ignore\n    metrics:\n      metric:\n        - not IsMatch(name, \"^(otelcol_loadbalancer_central_queue_compressed_bytes|otelcol_loadbalancer_central_queue_compressed_capacity|otelcol_loadbalancer_central_queue_compressed_capacity_bytes|otelcol_loadbalancer_central_queue_saturation|otelcol_loadbalancer_central_queue_inflight_uncompressed_bytes|otelcol_loadbalancer_central_queue_inflight_uncompressed_capacity|otelcol_loadbalancer_central_queue_inflight_uncompressed_capacity_bytes|otelcol_loadbalancer_central_queue_rejected_compressed_bytes|otelcol_loadbalancer_central_queue_rejected_compressed_bytes_total|otelcol_loadbalancer_central_queue_oldest_item_age|otelcol_loadbalancer_central_queue_oldest_item_age_milliseconds|otelcol_process_memory_rss|otelcol_process_memory_rss_bytes|otelcol_process_runtime_heap_alloc_bytes|otelcol_receiver_refused_log_records|otelcol_receiver_refused_log_records_total|otelcol_receiver_refused_metric_points|otelcol_receiver_refused_metric_points_total|otelcol_receiver_refused_spans|otelcol_receiver_refused_spans_total|otelcol_processor_refused_log_records|otelcol_processor_refused_log_records_total|otelcol_processor_refused_metric_points|otelcol_processor_refused_metric_points_total|otelcol_processor_refused_spans|otelcol_processor_refused_spans_total)$\")\nservice:\n  pipelines:\n    metrics/pressure_readiness:\n      receivers:\n        - forward\n      processors:\n        - filter/pressure_readiness\n      exporters:\n        - prometheus/pressure_readiness\n" $pressurePrometheusEndpoint)) }}
  {{- $config = merge $config $pressureOverlay }}
{{- end }}
{{- if eq .Values.telemetryExternalConfig.type "prometheus" }}
  {{- include "sawmills-collector.applyPrometheusRemoteWriteExternalLabels" (dict "root" . "config" $config) }}
  {{- include "sawmills-collector.removePrometheusRemoteWriteExternalLabelProcessor" (dict "config" $config) }}
{{- end }}
{{- if and (eq (include "sawmills-collector.usesExternalLabelProcessor" (dict "config" $config)) "true") (hasKey $config "processors") (hasKey $config.processors "transform/external_labels") .Values.prometheusremotewrite .Values.prometheusremotewrite.external_labels }}
  {{- $processor := include "sawmills-collector.externalLabelsProcessor" . | fromYaml }}
  {{- $_ := set $config.processors "transform/external_labels" $processor }}
{{- end }}
{{- end }}
{{- include "sawmills-collector.addTelemetryPprof" (dict "root" . "config" $config) }}
{{- toYaml $config }}
{{- end }}
{{- end -}}

{{/*
Convert a Go-style duration string into milliseconds.
Supported units: ms, s, m, h. Composite values are allowed, e.g. 1m30s.
*/}}
{{- define "sawmills-collector.durationToMilliseconds" -}}
{{- $duration := toString . -}}
{{- $matches := regexFindAll "[0-9]+(?:ms|s|m|h)" $duration -1 -}}
{{- if or (eq (len $matches) 0) (ne (join "" $matches) $duration) -}}
{{- fail (printf "unsupported duration %q; use Go-style duration values such as 15s, 1m, or 1500ms" $duration) -}}
{{- end -}}
{{- $total := 0 -}}
{{- range $match := $matches -}}
  {{- $value := atoi (regexFind "[0-9]+" $match) -}}
  {{- if hasSuffix "ms" $match -}}
    {{- $total = add $total $value -}}
  {{- else if hasSuffix "s" $match -}}
    {{- $total = add $total (mul $value 1000) -}}
  {{- else if hasSuffix "m" $match -}}
    {{- $total = add $total (mul $value 60000) -}}
  {{- else if hasSuffix "h" $match -}}
    {{- $total = add $total (mul $value 3600000) -}}
  {{- end -}}
{{- end -}}
{{- $total -}}
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

{{/*
Compute effective replica count (always at least 1).
*/}}
{{- define "sawmills-collector.replicaCountValue" -}}
{{- $replicas := int (default 1 .Values.replicaCount) -}}
{{- if lt $replicas 1 -}}
  {{- $replicas = 1 -}}
{{- end -}}
{{- $replicas -}}
{{- end }}

{{/*
Default maxUnavailable based on replica count.
*/}}
{{- define "sawmills-collector.defaultMaxUnavailable" -}}
{{- $replicas := include "sawmills-collector.replicaCountValue" . | int -}}
{{- if gt $replicas 10 -}}
  {{- $val := div (add $replicas 4) 5 -}}
  {{- if lt $val 2 -}}
2
  {{- else -}}
{{ $val }}
  {{- end -}}
{{- else -}}
1
{{- end -}}
{{- end }}

{{/*
Default maxSurge based on replica count.
*/}}
{{- define "sawmills-collector.defaultMaxSurge" -}}
{{- $replicas := include "sawmills-collector.replicaCountValue" . | int -}}
{{- if gt $replicas 10 -}}
  {{- $val := div (add $replicas 4) 5 -}}
  {{- if lt $val 2 -}}
2
  {{- else -}}
{{ $val }}
  {{- end -}}
{{- else -}}
2
{{- end -}}
{{- end }}

{{/*
Default PodDisruptionBudget minAvailable.
*/}}
{{- define "sawmills-collector.defaultPdbMinAvailable" -}}
{{- $replicas := include "sawmills-collector.replicaCountValue" . | int -}}
{{- if le $replicas 5 -}}
  {{- $val := sub $replicas 1 -}}
  {{- if lt $val 0 -}}
0
  {{- else -}}
{{ $val }}
  {{- end -}}
{{- else -}}
  {{- $val := div (add (mul $replicas 8) 9) 10 -}}
  {{- if lt $val 2 -}}
2
  {{- else -}}
{{ $val }}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Default LB PodDisruptionBudget minAvailable.
For LB we always want at least 2 pods running to avoid single-point-of-failure.
  1 replica:   0 (PDB would block all voluntary disruptions otherwise)
  2-3 replicas: replicas - 1
  > 3 replicas: ceil(0.66 * replicas), min 2
*/}}
{{- define "sawmills-collector.defaultLbPdbMinAvailable" -}}
{{- $replicas := int (default 3 .Values.loadBalancer.replicas) -}}
{{- if le $replicas 1 -}}
0
{{- else if le $replicas 3 -}}
{{ sub $replicas 1 }}
{{- else -}}
  {{- $val := div (add (mul $replicas 2) 2) 3 -}}
  {{- if lt $val 2 -}}
2
  {{- else -}}
{{ $val }}
  {{- end -}}
{{- end -}}
{{- end }}


{{/*
Compute GOMEMLIMIT as 90% of a Kubernetes memory value (e.g. "4Gi" → "3686MiB").
Accepts Gi and Mi suffixes. Fails at template time for unrecognized formats
to prevent invalid GOMEMLIMIT values that would crash Go pods at startup.
*/}}
{{- define "sawmills-collector.goMemLimit" -}}
{{- $raw := . | toString -}}
{{- if hasSuffix "Gi" $raw -}}
  {{- $num := trimSuffix "Gi" $raw | float64 -}}
  {{- $mib := mulf $num 1024 | mulf 0.9 | ceil | int -}}
  {{- printf "%dMiB" $mib -}}
{{- else if hasSuffix "Mi" $raw -}}
  {{- $num := trimSuffix "Mi" $raw | float64 -}}
  {{- $mib := mulf $num 0.9 | ceil | int -}}
  {{- printf "%dMiB" $mib -}}
{{- else -}}
  {{- fail (printf "goMemLimit: unsupported memory format %q — use Gi or Mi (e.g. \"4Gi\", \"512Mi\")" $raw) -}}
{{- end -}}
{{- end }}

{{/*
Compute Kubernetes memory quantity bytes for backend_drain pressure checks.
Accepts Gi and Mi suffixes to match the existing GOMEMLIMIT helper.
*/}}
{{- define "sawmills-collector.memoryBytes" -}}
{{- $raw := . | toString -}}
{{- if hasSuffix "Gi" $raw -}}
  {{- $num := trimSuffix "Gi" $raw | float64 -}}
  {{- printf "%.0f" (mulf $num 1073741824) -}}
{{- else if hasSuffix "Mi" $raw -}}
  {{- $num := trimSuffix "Mi" $raw | float64 -}}
  {{- printf "%.0f" (mulf $num 1048576) -}}
{{- else -}}
  {{- fail (printf "memoryBytes: unsupported memory format %q — use Gi or Mi (e.g. \"4Gi\", \"512Mi\")" $raw) -}}
{{- end -}}
{{- end }}

{{/*
Check if any HAProxy mapping has TLS enabled (only when HAProxy is actually enabled)
*/}}
{{- define "sawmills-collector.haproxyTlsEnabled" -}}
{{- if not .Values.haproxy.enabled -}}
false
{{- else -}}
{{- $tlsEnabled := false -}}
{{- range $name, $config := .Values.haproxy.mapping -}}
  {{- if and $config.tls $config.tls.enabled -}}
    {{- $tlsEnabled = true -}}
  {{- end -}}
{{- end -}}
{{- $tlsEnabled -}}
{{- end -}}
{{- end -}}

{{/*
Check if TLS certificate data is provided in values (vs referencing an existing secret)
Returns explicit "true" or "false" for consistent comparison with haproxyTlsEnabled
*/}}
{{- define "sawmills-collector.haproxyTlsCertProvided" -}}
{{- if and .Values.haproxy.tls .Values.haproxy.tls.certificate .Values.haproxy.tls.privateKey -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Check if sibling fallback is enabled.
Requires loadBalancer + HAProxy to be enabled, and sibling_fallback.enabled to be true.
Returns "true" or "false" as string for consistent comparison.
*/}}
{{- define "sawmills-collector.siblingFallbackEnabled" -}}
{{- if and .Values.loadBalancer.enabled .Values.haproxy.enabled .Values.haproxy.sibling_fallback.enabled -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Check if external fallback is enabled.
Defaults to true for backward compatibility.
Returns "true" or "false" as string.
*/}}
{{- define "sawmills-collector.externalFallbackEnabled" -}}
{{- $cfg := default dict .Values.haproxy.external_fallback -}}
{{- if kindIs "map" $cfg -}}
  {{- if hasKey $cfg "enabled" -}}
    {{- if $cfg.enabled -}}true{{- else -}}false{{- end -}}
  {{- else -}}
true
  {{- end -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Get the fully qualified headless service name for sibling fallback DNS resolution.
Returns the stable external headless service DNS name
"<fullname>-headless.<namespace>.svc.cluster.local".
Note: assumes default cluster domain (cluster.local).
*/}}
{{- define "sawmills-collector.lbHeadlessSvcFQDN" -}}
{{- printf "%s-headless.%s.svc.cluster.local" (include "sawmills-collector.fullname" .) .Release.Namespace -}}
{{- end -}}

{{/*
Get the KEDA external scaler resource name.
Returns "<fullname>-keda-otel-scaler", keeping the DNS label <= 63 chars.
*/}}
{{- define "sawmills-collector.kedaScalerName" -}}
{{- printf "%s-keda-otel-scaler" (include "sawmills-collector.fullname" . | trunc 46 | trimSuffix "-") | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Get the fully qualified KEDA external scaler service name.
Returns "<keda-scaler-name>.<namespace>.svc.cluster.local".
*/}}
{{- define "sawmills-collector.kedaScalerSvcFQDN" -}}
{{- printf "%s.%s.svc.cluster.local" (include "sawmills-collector.kedaScalerName" .) .Release.Namespace -}}
{{- end -}}

{{/*
Get the load balancer KEDA ScaledObject name.
Use distinct names for the external scaler trigger families so KEDA creates a
fresh child HPA when migrating from legacy CPU/resource-backed ScaledObjects.
Legacy Prometheus and resource-only configurations keep the original name.
*/}}
{{- define "sawmills-collector.loadBalancerKedaScaledObjectName" -}}
{{- $suffix := "-lb-keda-hpa" -}}
{{- $external := .Values.loadBalancer.keda.scaling.external -}}
{{- $triggerType := default "external" $external.loadBalancerTriggerType -}}
{{- if and $external.enabled (eq $triggerType "external") -}}
{{- $suffix = "-lb-keda-external-hpa" -}}
{{- else if and $external.enabled (eq $triggerType "metrics-api") -}}
{{- $suffix = "-lb-keda-metrics-api-hpa" -}}
{{- end -}}
{{- printf "%s%s" (include "sawmills-collector.fullname" . | trunc 39 | trimSuffix "-") $suffix | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Build a KEDA metrics-api URL for the scaler monitoring HTTP endpoint.
Call with dict "root" set to the chart root context and "query" set to the
plain query string. Requires kedaScaler.enabled=true. Returns:
"http://<keda-scaler-service>:<monitoringPort>/query?query=<urlencoded-query>".
*/}}
{{- define "sawmills-collector.kedaMetricsAPIURL" -}}
{{- if not .root.Values.kedaScaler.enabled -}}
{{- fail "kedaScaler.enabled must be true when keda.scaling.external.loadBalancerTriggerType is metrics-api" -}}
{{- end -}}
{{- $query := required "keda.scaling.external.loadBalancerMetadata.query is required for metrics-api" .query -}}
{{- printf "http://%s:%v/query?query=%s" (include "sawmills-collector.kedaScalerSvcFQDN" .root) .root.Values.kedaScaler.service.monitoringPort (urlquery $query) -}}
{{- end -}}

{{/*
Build a KEDA metrics-api URL for the load balancer scaler monitoring HTTP endpoint.
Call with dict "root" set to the chart root context and "query" set to the
plain query string. Requires kedaScaler.enabled=true. Fails if kedaScaler.enabled
is false or the required query metadata is missing. Uses
.root.Values.kedaScaler.service.monitoringPort. Returns:
"http://<keda-scaler-service>:<monitoringPort>/query?query=<urlencoded-query>".
*/}}
{{- define "sawmills-collector.loadBalancerKedaMetricsAPIURL" -}}
{{- if not .root.Values.kedaScaler.enabled -}}
{{- fail "kedaScaler.enabled must be true when loadBalancer.keda.scaling.external.loadBalancerTriggerType is metrics-api" -}}
{{- end -}}
{{- $query := required "loadBalancer.keda.scaling.external.metadata.query is required for metrics-api" .query -}}
{{- printf "http://%s:%v/query?query=%s" (include "sawmills-collector.kedaScalerSvcFQDN" .root) .root.Values.kedaScaler.service.monitoringPort (urlquery $query) -}}
{{- end -}}

{{/*
Resolve whether to use native sidecar mode for HAProxy.
Accepts .Values.haproxy.nativeSidecar: "false" | "true" | "auto"
Returns "true" or "false" as a string.
*/}}
{{- define "sawmills-collector.useNativeSidecar" -}}
{{- $mode := default "false" .Values.haproxy.nativeSidecar | toString -}}
{{- if eq $mode "true" -}}
true
{{- else if eq $mode "auto" -}}
{{- if semverCompare ">=1.33-0" .Capabilities.KubeVersion.Version -}}
true
{{- else -}}
false
{{- end -}}
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Validate load balancer queue compression settings for direct otelCollectorConfig mode.
Fail fast for known invalid combinations.
*/}}
{{- define "sawmills-collector.validateLoadBalancerQueueCompression" -}}
{{- $lbOtelConfig := default dict .Values.loadBalancer.otelConfig -}}
{{- if and .Values.loadBalancer.enabled (not (default "" $lbOtelConfig.s3path)) -}}
{{- $cfg := default dict .Values.loadBalancer.otelCollectorConfig -}}
{{- $exporters := default dict (get $cfg "exporters") -}}
{{- range $name, $exporter := $exporters -}}
  {{- if and (hasPrefix "loadbalancing" $name) (kindIs "map" $exporter) -}}
    {{- $sendingQueue := default dict (get $exporter "sending_queue") -}}
    {{- if kindIs "map" $sendingQueue -}}
      {{- $storage := get $sendingQueue "storage" -}}
      {{- if and $storage (ne (toString $storage) "") (not $.Values.loadBalancer.storage.enabled) -}}
        {{- fail (printf "loadBalancer.storage.enabled must be true when exporters.%s.sending_queue.storage is set" $name) -}}
      {{- end -}}

      {{- $compressInMemory := default false (get $sendingQueue "compress_in_memory") -}}
      {{- if $compressInMemory -}}
        {{- /* sending_queue.enabled defaults to true when omitted */ -}}
        {{- $enabled := get $sendingQueue "enabled" -}}
        {{- if and (ne $enabled nil) (not (or (eq $enabled true) (eq (toString $enabled) "true"))) -}}
          {{- fail (printf "exporters.%s.sending_queue.compress_in_memory requires sending_queue.enabled=true" $name) -}}
        {{- end -}}

        {{- $payloadCompression := lower (toString (default "" (get $sendingQueue "payload_compression"))) -}}
        {{- if not (or (eq $payloadCompression "snappy") (eq $payloadCompression "zstd")) -}}
          {{- fail (printf "exporters.%s.sending_queue.compress_in_memory requires sending_queue.payload_compression to be snappy or zstd" $name) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate local backend healthcheck has a chart-rendered backend_drain endpoint.
*/}}
{{- define "sawmills-collector.validateHaproxyLocalBackendHealthcheck" -}}
{{- $localBackendHealthcheck := .Values.haproxy.local_backend_healthcheck | default dict -}}
{{- if ($localBackendHealthcheck.enabled | default false) -}}
{{- $lbPressureReadiness := .Values.loadBalancer.pressureReadiness | default dict -}}
{{- $mainDrain := .Values.rollout.main.drain | default dict -}}
{{- $mainDrainConfigSource := default "overlay" $mainDrain.configSource -}}
{{- $lbPressureBackendDrainRendered := and .Values.loadBalancer.enabled ($lbPressureReadiness.enabled | default false) -}}
{{- $mainDrainBackendDrainRendered := and .Values.loadBalancer.enabled ($mainDrain.enabled | default false) (eq $mainDrainConfigSource "overlay") -}}
{{- if not (or $lbPressureBackendDrainRendered $mainDrainBackendDrainRendered) -}}
{{- fail "haproxy.local_backend_healthcheck.enabled requires chart-rendered backend_drain via loadBalancer.pressureReadiness.enabled=true or rollout.main.drain.enabled=true with configSource=overlay" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
HAProxy container spec (shared between native sidecar and regular container paths).
Caller passes context via dict with "root" (top-level context) and "nativeSidecar" (bool).
*/}}
{{- define "sawmills-collector.haproxyContainer" -}}
{{- $root := .root -}}
{{- $nativeSidecar := .nativeSidecar -}}
{{- $livenessType := (dig "probes" "liveness" "type" "http" $root.Values.haproxy) | toString | lower -}}
{{- $livenessPort := dig "probes" "liveness" "port" 13135 $root.Values.haproxy -}}
{{- $livenessPath := dig "probes" "liveness" "path" "/healthcheck" $root.Values.haproxy -}}
{{- $readinessType := (dig "probes" "readiness" "type" "http" $root.Values.haproxy) | toString | lower -}}
{{- $readinessPort := dig "probes" "readiness" "port" 13135 $root.Values.haproxy -}}
{{- $readinessPath := dig "probes" "readiness" "path" "/ready" $root.Values.haproxy -}}
{{- $localBackendHealthcheck := $root.Values.haproxy.local_backend_healthcheck | default dict -}}
{{- $lbPressureReadiness := $root.Values.loadBalancer.pressureReadiness | default dict -}}
{{- $lbPressureReadinessUseForPodReadiness := true -}}
{{- if hasKey $lbPressureReadiness "useForPodReadiness" -}}
{{- $lbPressureReadinessUseForPodReadiness = $lbPressureReadiness.useForPodReadiness -}}
{{- end -}}
{{- $pressureKeepsPodReady := and $root.Values.loadBalancer.enabled ($lbPressureReadiness.enabled | default false) (not $lbPressureReadinessUseForPodReadiness) -}}
{{- if or ($localBackendHealthcheck.enabled | default false) $pressureKeepsPodReady -}}
{{- /* Keep HAProxy's Kubernetes readiness shallow when HAProxy owns fallback decisions. */ -}}
{{- if eq $livenessType "tcp" -}}
{{- $readinessType = "tcp" -}}
{{- $readinessPort = $livenessPort -}}
{{- else -}}
{{- $readinessType = "http" -}}
{{- $readinessPort = $livenessPort -}}
{{- $readinessPath = $livenessPath -}}
{{- end -}}
{{- end -}}
{{- $defaultSecurityContext := dict "runAsNonRoot" true "runAsUser" 99 "runAsGroup" 99 -}}
{{- $securityContext := mergeOverwrite (deepCopy $defaultSecurityContext) (default dict $root.Values.haproxy.securityContext) -}}
{{- if not (or (eq $livenessType "http") (eq $livenessType "tcp")) -}}
{{- fail (printf "haproxy.probes.liveness.type must be one of [http, tcp], got %q" $livenessType) -}}
{{- end -}}
{{- if not (or (eq $readinessType "http") (eq $readinessType "tcp")) -}}
{{- fail (printf "haproxy.probes.readiness.type must be one of [http, tcp], got %q" $readinessType) -}}
{{- end -}}
- name: haproxy
  image: {{ include "sawmills-collector.haproxyImage" $root }}
  securityContext:
    {{- toYaml $securityContext | nindent 4 }}
  {{- if $nativeSidecar }}
  restartPolicy: Always
  {{- end }}
  env:
    - name: MY_POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
  ports:
  {{- range $name, $config := $root.Values.haproxy.mapping }}
  - containerPort: {{ $config.from }}
    name: {{ $name }}
    protocol: {{ $config.to.protocol }}
  {{- end }}
  livenessProbe:
    {{- if eq $livenessType "tcp" }}
    tcpSocket:
      port: {{ $livenessPort }}
    {{- else }}
    httpGet:
      path: {{ $livenessPath }}
      port: {{ $livenessPort }}
    {{- end }}
    initialDelaySeconds: {{ $root.Values.rollout.haproxy.probes.liveness.initialDelaySeconds }}
    periodSeconds: {{ $root.Values.rollout.haproxy.probes.liveness.periodSeconds }}
    failureThreshold: {{ $root.Values.rollout.haproxy.probes.liveness.failureThreshold }}
  readinessProbe:
    {{- if eq $readinessType "tcp" }}
    tcpSocket:
      port: {{ $readinessPort }}
    {{- else }}
    httpGet:
      path: {{ $readinessPath }}
      port: {{ $readinessPort }}
    {{- end }}
    initialDelaySeconds: {{ $root.Values.rollout.haproxy.probes.readiness.initialDelaySeconds }}
    periodSeconds: {{ $root.Values.rollout.haproxy.probes.readiness.periodSeconds }}
  {{- if $nativeSidecar }}
  lifecycle:
    preStop:
      exec:
        command:
          - /bin/sh
          - -c
          - "kill -USR1 1 2>/dev/null || true"
  {{- else }}
  lifecycle:
    preStop:
      exec:
        command:
          - /bin/sh
          - -c
          - "sleep 3; kill -USR1 1 2>/dev/null || true"
  {{- end }}
  resources:
    {{- if $root.Values.haproxy.resources.requests }}
    requests:
      {{- toYaml $root.Values.haproxy.resources.requests | nindent 6 }}
    {{- end }}
    {{- if not $root.Values.haproxy.resources.disableLimits }}
    limits:
      {{- toYaml $root.Values.haproxy.resources.limits | nindent 6 }}
    {{- end }}
  volumeMounts:
  - name: haproxy-config
    mountPath: /usr/local/etc/haproxy/haproxy.cfg
    subPath: haproxy.cfg
  {{- if eq (include "sawmills-collector.haproxyTlsEnabled" $root) "true" }}
  - name: haproxy-tls-secret
    mountPath: {{ $root.Values.haproxy.tls.certPath }}
    readOnly: true
  {{- end }}
{{- end -}}

{{/*
Get the HAProxy TLS secret name - either generated or user-provided
*/}}
{{- define "sawmills-collector.haproxyTlsSecretName" -}}
{{- if and .Values.haproxy.tls .Values.haproxy.tls.certificate .Values.haproxy.tls.privateKey -}}
{{- printf "%s-haproxy-tls" (include "sawmills-collector.fullname" .) -}}
{{- else if and .Values.haproxy.tls .Values.haproxy.tls.secretName -}}
{{- .Values.haproxy.tls.secretName -}}
{{- else -}}
{{- fail "Either haproxy.tls.secretName or both haproxy.tls.certificate and haproxy.tls.privateKey must be provided when TLS is enabled" -}}
{{- end -}}
{{- end -}}
