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
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
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
{{- if .Values.resourceBaseName -}}
{{- include "sawmills-collector.resourceBaseName" . }}
{{- else -}}
{{- .Release.Name }}
{{- end }}
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
{{- $config := deepCopy .Values.telemetryConfig }}
{{- if .Values.haproxy.enabled }}
  {{- $config = merge $config .Values.haproxyConfig }}
{{- end }}
{{- if eq .Values.telemetryExternalConfig.type "prometheus" }}
  {{- $config = merge $config .Values.telemetryExternalConfig.prometheusConfig }}
{{- else if eq .Values.telemetryExternalConfig.type "arrow" }}
  {{- $config = merge $config .Values.telemetryExternalConfig.arrowConfig }}
{{- end }}
{{- /* LB-only remote-operator OTLP ingest wiring (receiver + dedicated pipeline). */ -}}
{{- $lbOverlay := (fromYaml (printf "receivers:\n  otlp/remote_operator:\n    protocols:\n      http:\n        endpoint: ${env:MY_POD_IP}:%v\nprocessors:\n  transform/remove_unit_preserve_service_name:\n    error_mode: ignore\n    metric_statements:\n      - context: metric\n        statements:\n          - set(metric.unit, \"\")\nservice:\n  pipelines:\n    metrics/remote_operator:\n      receivers:\n        - otlp/remote_operator\n      processors:\n        - memory_limiter\n        - transform/remove_unit_preserve_service_name\n        - deltatocumulative\n        - batch\n      exporters:\n        - routing\n        - forward\n" (.Values.telemetry.remoteOperatorOtlpHttpPort | default 14319))) }}
{{- $config = merge $config $lbOverlay }}
{{- /* Override transform/external_labels processor with dynamic config */ -}}
{{- if and (hasKey $config "processors") (hasKey $config.processors "transform/external_labels") .Values.prometheusremotewrite .Values.prometheusremotewrite.external_labels }}
  {{- $processor := include "sawmills-collector.externalLabelsProcessor" . | fromYaml }}
  {{- $_ := set $config.processors "transform/external_labels" $processor }}
{{- end }}
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
