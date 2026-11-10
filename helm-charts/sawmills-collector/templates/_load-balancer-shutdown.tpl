{{/* Validate the LB shutdown phases against the Pod's termination grace. */}}
{{- define "sawmills-collector.loadBalancerShutdownBudgetMilliseconds" -}}
{{- $root := .root -}}
{{- if not (regexMatch "^[0-9]+$" (toString $root.Values.rollout.loadBalancer.preStopSleepSeconds)) -}}
  {{- fail "LB shutdown budget requires integer rollout.loadBalancer.preStopSleepSeconds" -}}
{{- end -}}
{{- $budget := $root.Values.loadBalancer.shutdownBudget | default dict -}}
{{- $centralMs := 0 -}}
{{- $remote := default "" ($root.Values.loadBalancer.otelConfig | default dict).s3path -}}
{{- if not $remote -}}
{{- $config := $root.Values.loadBalancer.otelCollectorConfig | default dict -}}
{{- range $name, $exporter := ($config.exporters | default dict) -}}
  {{- if and (hasPrefix "loadbalancing" $name) (kindIs "map" $exporter) -}}
    {{- $queue := $exporter.central_queue | default dict -}}
    {{- if $queue.enabled -}}
      {{- $timeoutMs := include "sawmills-collector.shutdownDurationMilliseconds" (default "5m" $queue.shutdown_timeout) | int64 -}}
      {{- if le $timeoutMs 0 -}}
        {{- fail "LB shutdown budget requires a positive central_queue.shutdown_timeout" -}}
      {{- end -}}
      {{- $centralMs = add $centralMs $timeoutMs -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
{{- $declaredDrain := $budget.centralQueueDrain | default "" -}}
{{- if and $remote (not $declaredDrain) -}}
  {{- fail "LB shutdown budget requires loadBalancer.shutdownBudget.centralQueueDrain for external/S3 collector configuration" -}}
{{- end -}}
{{- if $declaredDrain -}}
  {{- $declaredMs := include "sawmills-collector.shutdownDurationMilliseconds" $declaredDrain | int64 -}}
  {{- if lt $declaredMs $centralMs -}}
    {{- fail "LB shutdown budget centralQueueDrain must cover the sum of inline central_queue.shutdown_timeout values" -}}
  {{- end -}}
  {{- $centralMs = max $centralMs $declaredMs -}}
{{- end -}}
{{- $telemetryMs := include "sawmills-collector.shutdownDurationMilliseconds" (default "30s" $budget.telemetryExport) | int64 -}}
{{- $cleanupMs := include "sawmills-collector.shutdownDurationMilliseconds" (default "10s" $budget.cleanupReserve) | int64 -}}
{{- if or (le $telemetryMs 0) (le $cleanupMs 0) (lt (int $root.Values.rollout.loadBalancer.preStopSleepSeconds) 0) -}}
  {{- fail "LB shutdown budget requires positive telemetryExport/cleanupReserve and nonnegative preStopSleepSeconds" -}}
{{- end -}}
{{- $hookMs := max (mul 1000 (int $root.Values.rollout.loadBalancer.preStopSleepSeconds)) (mul 1000 .drainRequestSeconds) -}}
{{- $totalMs := add $hookMs $centralMs $telemetryMs $cleanupMs -}}
{{- $pressure := $root.Values.loadBalancer.pressureReadiness | default dict -}}
{{- if $pressure.waitForQueue -}}
  {{- $reserveMs := include "sawmills-collector.durationToMilliseconds" (default "310s" $pressure.shutdownReserve) | int64 -}}
  {{- /* The existing queue-wait check requires strict room beyond hook + reserve. */ -}}
  {{- $totalMs = max $totalMs (add $hookMs $reserveMs 1) -}}
{{- end -}}
{{- $totalMs -}}
{{- end -}}

{{/* time.Duration.String can emit fractional seconds and sub-millisecond units. */}}
{{- define "sawmills-collector.shutdownDurationMilliseconds" -}}
{{- $duration := toString . -}}
{{- $parts := regexFindAll "[0-9]+(?:\\.[0-9]+)?(?:ns|us|µs|μs|ms|s|m|h)" $duration -1 -}}
{{- if or (eq (len $parts) 0) (ne (join "" $parts) $duration) -}}
  {{- fail (printf "unsupported shutdown budget duration %q" $duration) -}}
{{- end -}}
{{- $units := dict "h" 3600000.0 "m" 60000.0 "s" 1000.0 "ms" 1.0 "us" 0.001 "µs" 0.001 "μs" 0.001 "ns" 0.000001 -}}
{{- $total := 0.0 -}}
{{- range $part := $parts -}}
  {{- $value := regexFind "^[0-9]+(?:\\.[0-9]+)?" $part | float64 -}}
  {{- $unit := regexFind "[^0-9.]+$" $part -}}
  {{- $total = addf $total (mulf $value (get $units $unit)) -}}
{{- end -}}
{{- if gt $total 9223372036854.0 -}}
  {{- fail "shutdown budget duration exceeds Go time.Duration range" -}}
{{- end -}}
{{- ceil $total | int64 -}}
{{- end -}}
