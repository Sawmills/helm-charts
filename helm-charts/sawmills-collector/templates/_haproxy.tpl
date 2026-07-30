{{- define "sawmills-collector.haproxy.config" -}}
{{- $refusalFastFail := .Values.haproxy.refusal_fast_fail | default dict -}}
{{- $healthcheck := .Values.haproxy.healthcheck | default dict -}}
{{- $forwardingHealth := $healthcheck.forwarding_health | default dict -}}
{{- $localBackendHealthcheck := .Values.haproxy.local_backend_healthcheck | default dict -}}
{{- $localBackendHealthcheckEnabled := $localBackendHealthcheck.enabled | default false -}}
{{- $forwardingHealthEnabled := or ($forwardingHealth.enabled | default false) $localBackendHealthcheckEnabled -}}
{{- $localBackendHealthcheckPort := $localBackendHealthcheck.port | default 13137 -}}
{{- $localBackendHealthcheckPath := $localBackendHealthcheck.path | default "/ready" -}}
{{- $localBackendHealthcheckInterval := $localBackendHealthcheck.interval | default 3000 -}}
{{- $localBackendHealthcheckRise := $localBackendHealthcheck.rise | default 2 -}}
{{- $localBackendHealthcheckFall := $localBackendHealthcheck.fall | default 2 -}}
{{- $readinessPath := dig "probes" "readiness" "path" "/ready" .Values.haproxy -}}
{{- $haproxyDefaults := .Values.haproxy.defaults | default dict -}}
{{- $haproxyDefaultOptions := $haproxyDefaults.options | default list -}}
{{- $activeSiblingLoadBalancing := false -}}
{{- if and (eq (include "sawmills-collector.siblingFallbackEnabled" .) "true") (.Values.haproxy.sibling_fallback.load_balance | default false) -}}
  {{- range $_, $mapping := .Values.haproxy.mapping -}}
    {{- if eq (($mapping.to | default dict).mode | default "http") "http" -}}
      {{- $activeSiblingLoadBalancing = true -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

global
{{- with .Values.haproxy.global }}
  {{- if .log }}log {{ .log }}{{- end }}
  {{- if .maxconn }}maxconn {{ .maxconn }}{{- else }}maxconn {{ $.Values.haproxy.max_connections }}{{- end }}
  {{- if .nbthread }}nbthread {{ .nbthread }}{{- end }}
  {{- if .daemon }}daemon{{- else }}daemon{{- end }}
{{- else }}
  log stdout format raw local0 info
  maxconn {{ .Values.haproxy.max_connections }}
  daemon
{{- end }}

{{- if eq (include "sawmills-collector.haproxyTlsEnabled" .) "true" }}
crt-store k8s-tls
  crt-base {{ .Values.haproxy.tls.certPath }}/
  key-base {{ .Values.haproxy.tls.certPath }}/
  load crt "tls.crt" key "tls.key" alias "haproxy-cert"
{{- end }}

defaults
{{- with .Values.haproxy.defaults }}
  {{- if .mode }}
  mode {{ .mode }}
  {{- end }}
  {{- if .timeout }}
  {{- if .timeout.connect }}
  timeout connect {{ .timeout.connect }}
  {{- else }}
  timeout connect 5s
  {{- end }}
  {{- if .timeout.client }}
  timeout client {{ .timeout.client }}
  {{- else }}
  timeout client 5s
  {{- end }}
  {{- if .timeout.server }}
  timeout server {{ .timeout.server }}
  {{- else }}
  timeout server 5s
  {{- end }}
  {{- if (index .timeout "http-request") }}
  timeout http-request {{ index .timeout "http-request" }}
  {{- else }}
  timeout http-request 10s
  {{- end }}
  {{- else }}
  timeout connect 5s
  timeout client 5s
  timeout server 5s
  timeout http-request 10s
  {{- end }}
  {{- if .retries }}
  retries {{ .retries }}
  {{- else }}
  retries 3
  {{- end }}
  {{- if .log }}
  log {{ .log }}
  {{- else }}
  log global
  {{- end }}
  {{- range .options }}
  option {{ . }}
  {{- end }}
{{- else }}
  timeout connect 5s
  timeout client 5s
  timeout server 5s
  retries 3
  log global
  {{- if not $activeSiblingLoadBalancing }}
  option redispatch
  {{- end }}
{{- end }}

{{- if eq (include "sawmills-collector.siblingFallbackEnabled" .) "true" }}
resolvers k8s
  parse-resolv-conf
  hold valid {{ .Values.haproxy.sibling_fallback.resolver.hold_valid | default "5s" }}
  hold timeout {{ .Values.haproxy.sibling_fallback.resolver.hold_timeout | default "5s" }}
  hold refused {{ .Values.haproxy.sibling_fallback.resolver.hold_refused | default "5s" }}
  accepted_payload_size 8192
{{- end }}

{{- if .Values.haproxy.prometheus.enabled }}
frontend prometheus
  bind *:{{ .Values.haproxy.prometheus.port | default 8405 }}
  mode http
  http-request use-service prometheus-exporter if { path /metrics }
  no log
{{- end }}

{{- if .Values.haproxy.stats.enabled }}
frontend stats
  mode http
  bind *:{{ .Values.haproxy.stats.port | default 8406 }}
  stats enable
  stats uri {{ .Values.haproxy.stats.uri | default "/" }}
  stats refresh {{ .Values.haproxy.stats.refresh | default "10s" }}
  stats auth {{ .Values.haproxy.stats.auth | default "admin:admin" }}
  no log
{{- end }}

{{- if .Values.haproxy.healthcheck.enabled }}
frontend healthcheck
  bind *:{{ .Values.haproxy.healthcheck.port | default 13135 }}
  mode http
  no log
  # Return 503 when HAProxy is stopping (graceful shutdown) - ensures K8s removes
  # endpoint before pod actually terminates, preventing fallback during scale-down
  acl is_stopping stopping
  http-request deny deny_status 503 if is_stopping
  acl readiness_check path {{ $readinessPath }}
  {{- range $name, $config := .Values.haproxy.mapping }}
  # Only return healthy if HAProxy's internal rise checks have marked otel server as UP
  acl backend_{{ $name }}_up srv_is_up(logs_http_{{ $config.from }}/otel)
  http-request deny deny_status 503 if readiness_check !backend_{{ $name }}_up
  {{- end }}
  {{- if $forwardingHealthEnabled }}
  # Direct traffic readiness also requires the local collector to have usable forwarding backends.
  acl forwarding_health_up srv_is_up(forwarding_health_backend/forwarding_health)
  http-request deny deny_status 503 if readiness_check !forwarding_health_up
  {{- end }}
  http-request return status 200 if readiness_check
  default_backend healthcheck_backend

backend healthcheck_backend
  mode http
  server otel "$MY_POD_IP":13133

{{- if $forwardingHealthEnabled }}
backend forwarding_health_backend
  mode http
  option httpchk GET {{ $forwardingHealth.path | default "/forwarding-health" }}
  server forwarding_health "$MY_POD_IP":{{ $forwardingHealth.port | default 13136 }} check inter {{ $forwardingHealth.interval | default 3000 }} rise {{ $forwardingHealth.rise | default 2 }} fall {{ $forwardingHealth.fall | default 2 }}
{{- end }}
{{- end }}

{{- $haproxyFrontendPorts := list }}
{{- range $_, $mapping := .Values.haproxy.mapping }}
  {{- $haproxyFrontendPorts = append $haproxyFrontendPorts (int $mapping.from) }}
{{- end }}
{{- $forbiddenActivePeerPorts := concat $haproxyFrontendPorts (list 13133 (int $localBackendHealthcheckPort) (int ($forwardingHealth.port | default 13136))) }}
{{- if .Values.haproxy.prometheus.enabled }}
  {{- $forbiddenActivePeerPorts = append $forbiddenActivePeerPorts (int (.Values.haproxy.prometheus.port | default 8405)) }}
{{- end }}
{{- if .Values.haproxy.stats.enabled }}
  {{- $forbiddenActivePeerPorts = append $forbiddenActivePeerPorts (int (.Values.haproxy.stats.port | default 8406)) }}
{{- end }}
{{- if .Values.haproxy.healthcheck.enabled }}
  {{- $forbiddenActivePeerPorts = append $forbiddenActivePeerPorts (int (.Values.haproxy.healthcheck.port | default 13135)) }}
{{- end }}
{{- range $name, $config := .Values.haproxy.mapping }}
{{ $to := $config.to | default dict }}
{{ $fc := $to.fallback_config | default $.Values.haproxy.fallback_config | default dict }}
{{ $mode := $to.mode | default "http" }}
{{ $proto := "" }}
{{ if eq $mode "grpc" }}
  {{ $proto = "proto h2" }}
{{ end }}
{{- $siblingEnabled := false }}
{{- if and (eq (include "sawmills-collector.siblingFallbackEnabled" $) "true") (ne $mode "tcp") }}
  {{- $siblingEnabled = true }}
{{- end }}
{{- $siblingLoadBalance := false }}
{{- if and $siblingEnabled (eq $mode "http") }}
  {{- $siblingLoadBalance = $activeSiblingLoadBalancing }}
{{- end }}
{{- if and $siblingLoadBalance (has (int $to.port) $forbiddenActivePeerPorts) }}
  {{- fail (printf "haproxy.mapping.%s.to.port must not match an HAProxy frontend or health/telemetry port when haproxy.sibling_fallback.load_balance=true" $name) }}
{{- end }}
{{- if and $siblingLoadBalance (not $localBackendHealthcheckEnabled) }}
  {{- fail "haproxy.local_backend_healthcheck.enabled must be true when haproxy.sibling_fallback.load_balance=true" }}
{{- end }}
{{- $sf := $.Values.haproxy.sibling_fallback }}
frontend logs_http_frontend_{{ $config.from }}
  {{- if and $config.tls $config.tls.enabled }}
  bind *:{{ $config.from }} ssl crt @k8s-tls/haproxy-cert{{- if eq $mode "grpc" }} alpn h2{{- end }}
  {{- else }}
  bind *:{{ $config.from }} {{ $proto }}
  {{- end }}
  mode {{ if eq $mode "grpc" }}http{{ else }}{{ $mode }}{{ end }}
  {{- if not $config.logging | default false }}
  no log
  {{- else }}
  option httplog
  {{- end }}
  {{- range $option := $config.options }}
  option {{ $option }}
  {{- end }}
  {{- with $fc }}
  {{- if .timeout }}
  {{ if .timeout.client }}timeout client {{ .timeout.client }}{{- end }}
  {{- end }}
  {{- end }}
  {{- if and $to.metrics_proxy_endpoint (ne $mode "tcp") }}
  # Metrics proxy: forward unsupported DD metrics endpoints directly to Datadog.
  # The DD agent's own DD-API-KEY header passes through transparently (same as fallback).
  # Placed before sibling-hop check so distribution_points/sketches are always proxied,
  # even on sibling-retried requests that would otherwise 405 on the direct backend.
  acl is_distribution_points path_beg /api/v1/distribution_points
  acl is_sketches path_beg /api/v1/sketches
  acl is_beta_sketches path_beg /api/beta/sketches
  use_backend datadog_metrics_direct_{{ $config.from }} if is_distribution_points or is_sketches or is_beta_sketches
  {{- end }}
  {{- if and $siblingEnabled (not $siblingLoadBalance) }}
  # Sibling fallback: detect forwarded requests to prevent routing loops (max 1 hop)
  acl is_sibling_hop hdr(X-Sibling-Hop) -m found
  use_backend logs_http_{{ $config.from }}_direct if is_sibling_hop
  {{- end }}
  default_backend logs_http_{{ $config.from }}

backend logs_http_{{ $config.from }}
  mode {{ if eq $mode "grpc" }}http{{ else }}{{ $mode }}{{ end }}
  {{- $localBackendHealthcheckApplies := and $localBackendHealthcheckEnabled (eq $mode "http") }}
  {{- if and $siblingEnabled (ne $mode "tcp") (or $siblingLoadBalance ($refusalFastFail.enabled | default false)) }}
  retry-on 503
  {{- end }}
  {{- if and $siblingLoadBalance (not (has "redispatch" $haproxyDefaultOptions)) }}
  option redispatch
  {{- end }}
  {{- if $siblingLoadBalance }}
  retries {{ if hasKey $sf "retries" }}{{ $sf.retries }}{{ else }}1{{ end }}
  {{- end }}
  {{- range $option := $config.backend_options }}
  option {{ $option }}
  {{- end }}
  {{- if $localBackendHealthcheckApplies }}
  option httpchk GET {{ $localBackendHealthcheckPath }}
  {{- else if not $config.backend_options }}
  {{- if not (eq $mode "grpc") }}
  option httpchk GET /healthcheck
  {{- end }}
  {{- end }}
  {{- with $fc }}
  {{- if .timeout }}
  {{ if .timeout.connect }}timeout connect {{ .timeout.connect }}{{- end }}
  {{ if .timeout.server }}timeout server {{ .timeout.server }}{{- end }}
  {{- end }}
  {{- end }}
  {{- $server := $fc.server | default dict -}}
  {{- $interval := default 2000 $server.interval -}}
  {{- $rise := default 10 $server.rise -}}
  {{- $fall := default 1 $server.fall }}
  {{- $errorLimit := $.Values.haproxy.error_limit }}
  {{- $slowstart := "" }}
  {{- $externalFallbackEnabled := eq (include "sawmills-collector.externalFallbackEnabled" $) "true" }}
  {{- $failoverEnabled := or $siblingEnabled $to.fallback_endpoint }}
  {{- if and ($refusalFastFail.enabled | default false) (ne $mode "tcp") }}
  {{- $errorLimit = ($refusalFastFail.error_limit | default 20) }}
  {{- $slowstart = ($refusalFastFail.slowstart | default "") }}
  {{- end }}
  {{- if $failoverEnabled }}
  {{- if and $siblingEnabled (not $siblingLoadBalance) }}
  # Tag request as sibling-forwarded before sending to sibling tier
  http-request set-header X-Sibling-Hop 1
  {{- end }}
  {{- if $localBackendHealthcheckApplies }}
  server otel "$MY_POD_IP":{{ $to.port }} {{ $proto }}{{ if $siblingLoadBalance }} backup{{ end }} check port {{ $localBackendHealthcheckPort }} inter {{ $localBackendHealthcheckInterval }} rise {{ $localBackendHealthcheckRise }} fall {{ $localBackendHealthcheckFall }} observe {{ if eq $mode "http" }}layer7{{ else }}layer4{{ end }} error-limit {{ $errorLimit }} on-error mark-down{{ if ne $slowstart "" }} slowstart {{ $slowstart }}{{ end }}
  {{- else }}
  server otel "$MY_POD_IP":{{ $to.port }} {{ $proto }}{{ if $siblingLoadBalance }} backup{{ end }} check port 13133 inter {{ $interval }} rise {{ $rise }} fall {{ $fall }} observe {{ if eq $mode "http" }}layer7{{ else }}layer4{{ end }} error-limit {{ $errorLimit }} on-error mark-down{{ if ne $slowstart "" }} slowstart {{ $slowstart }}{{ end }}
  {{- end }}
  {{- if $siblingEnabled }}
  {{- $defaultPeerCheckPort := 13136 }}
  {{- if $localBackendHealthcheckApplies }}
    {{- $defaultPeerCheckPort = $localBackendHealthcheckPort }}
  {{- end }}
  {{- $peerCheckPort := $sf.check.port | default $defaultPeerCheckPort }}
  {{- if $siblingLoadBalance }}
  {{- $configuredPeerCheckPort := int ($sf.check.port | default 0) }}
  {{- if and (ne $configuredPeerCheckPort 0) (ne $configuredPeerCheckPort (int $localBackendHealthcheckPort)) }}
    {{- fail (printf "haproxy.sibling_fallback.check.port must equal haproxy.local_backend_healthcheck.port (%v) when load_balance=true" $localBackendHealthcheckPort) }}
  {{- end }}
  {{- $peerCheckPort = $localBackendHealthcheckPort }}
  # Active sibling tier: spread requests across ready LB collectors to break
  # connection-level ingress stickiness. The peer port is validated against
  # every HAProxy frontend port, so a request cannot loop through this backend.
  {{- else }}
  # Sibling tier: round-robin across other LB pods via headless service DNS
  # "backup" ensures these only activate when local otel is DOWN
  {{- end }}
  {{- if not $siblingLoadBalance }}
  # Check port 13136 is served by the forwarding_health extension in
  # sawmills-collector (PR #811); chart + collector changes must ship together.
  {{- end }}
  server-template sibling {{ $sf.max_servers | default 10 }} {{ include "sawmills-collector.lbHeadlessSvcFQDN" $ }}:{{ if $siblingLoadBalance }}{{ $to.port }}{{ else }}{{ $config.from }}{{ end }} {{ $proto }} check port {{ $peerCheckPort }} inter {{ $sf.check.interval | default 3000 }} rise {{ $sf.check.rise | default 2 }} fall {{ $sf.check.fall | default 2 }}{{ if not $siblingLoadBalance }} backup{{ else }} observe layer7 error-limit {{ $errorLimit }} on-error mark-down slowstart {{ $sf.slowstart | default "30s" }}{{ end }} resolvers k8s init-addr none
  {{- end }}
  {{- if and $externalFallbackEnabled $to.fallback_endpoint }}
  {{- if $siblingEnabled }}
  # External fallback: last resort (listed after siblings, so HAProxy tries siblings first)
  {{- end }}
  server fallback {{ $to.fallback_endpoint }} {{ $proto }} backup {{ if (or (not (hasKey $to "fallback_ssl")) $to.fallback_ssl) }}ssl verify none{{ end }}
  {{- end }}
  {{- else }}
  {{- if $localBackendHealthcheckApplies }}
  server otel "$MY_POD_IP":{{ $to.port }} {{ $proto }} check port {{ $localBackendHealthcheckPort }} inter {{ $localBackendHealthcheckInterval }} rise {{ $localBackendHealthcheckRise }} fall {{ $localBackendHealthcheckFall }}
  {{- else }}
  server otel "$MY_POD_IP":{{ $to.port }} {{ $proto }} check {{ if not (eq $mode "grpc") }}port 13133{{ end }}
  {{- end }}
  {{- end }}

{{- if and $to.metrics_proxy_endpoint (ne $mode "tcp") }}
# Datadog metrics direct backend: forwards distribution_points/sketches to DD API
backend datadog_metrics_direct_{{ $config.from }}
  mode http
  server datadog {{ $to.metrics_proxy_endpoint }}:443 ssl verify required ca-file /etc/ssl/certs/ca-certificates.crt sni str({{ $to.metrics_proxy_endpoint }}) verifyhost {{ $to.metrics_proxy_endpoint }}
{{- end }}

{{- if and $siblingEnabled (not $siblingLoadBalance) }}
# Direct backend for sibling-forwarded requests (no sibling tier to prevent loops)
backend logs_http_{{ $config.from }}_direct
  mode {{ if eq $mode "grpc" }}http{{ else }}{{ $mode }}{{ end }}
  {{- range $option := $config.backend_options }}
  option {{ $option }}
  {{- end }}
  {{- if $localBackendHealthcheckApplies }}
  option httpchk GET {{ $localBackendHealthcheckPath }}
  {{- else if not $config.backend_options }}
  {{- if not (eq $mode "grpc") }}
  option httpchk GET /healthcheck
  {{- end }}
  {{- end }}
  {{- with $fc }}
  {{- if .timeout }}
  {{ if .timeout.connect }}timeout connect {{ .timeout.connect }}{{- end }}
  {{ if .timeout.server }}timeout server {{ .timeout.server }}{{- end }}
  {{- end }}
  {{- end }}
  # Strip sibling header before forwarding to local collector
  http-request del-header X-Sibling-Hop
  {{- $server := $fc.server | default dict -}}
  {{- $interval := default 2000 $server.interval -}}
  {{- $rise := default 10 $server.rise -}}
  {{- $fall := default 1 $server.fall }}
  {{- $directErrorLimit := $.Values.haproxy.error_limit }}
  {{- $directSlowstart := "" }}
  {{- $externalFallbackEnabled := eq (include "sawmills-collector.externalFallbackEnabled" $) "true" }}
  {{- if and ($refusalFastFail.enabled | default false) (ne $mode "tcp") }}
  {{- $directErrorLimit = ($refusalFastFail.error_limit | default 20) }}
  {{- $directSlowstart = ($refusalFastFail.slowstart | default "") }}
  {{- end }}
  {{- if $localBackendHealthcheckApplies }}
  server otel "$MY_POD_IP":{{ $to.port }} {{ $proto }} check port {{ $localBackendHealthcheckPort }} inter {{ $localBackendHealthcheckInterval }} rise {{ $localBackendHealthcheckRise }} fall {{ $localBackendHealthcheckFall }} observe {{ if eq $mode "http" }}layer7{{ else }}layer4{{ end }} error-limit {{ $directErrorLimit }} on-error mark-down{{ if ne $directSlowstart "" }} slowstart {{ $directSlowstart }}{{ end }}
  {{- else }}
  server otel "$MY_POD_IP":{{ $to.port }} {{ $proto }} check port 13133 inter {{ $interval }} rise {{ $rise }} fall {{ $fall }} observe {{ if eq $mode "http" }}layer7{{ else }}layer4{{ end }} error-limit {{ $directErrorLimit }} on-error mark-down{{ if ne $directSlowstart "" }} slowstart {{ $directSlowstart }}{{ end }}
  {{- end }}
  {{- if and $externalFallbackEnabled $to.fallback_endpoint }}
  server fallback {{ $to.fallback_endpoint }} {{ $proto }} backup {{ if (or (not (hasKey $to "fallback_ssl")) $to.fallback_ssl) }}ssl verify none{{ end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end -}} 
