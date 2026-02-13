{{- define "sawmills-collector.haproxy.config" -}}

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
  option redispatch
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
  bind *:{{ .Values.haproxy.prometheus.port | default .Values.haproxy.prometheus_port }}
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
  {{- range $name, $config := .Values.haproxy.mapping }}
  {{- if $config.to.fallback_endpoint }}
  # Only return healthy if HAProxy's internal rise checks have marked otel server as UP
  acl backend_{{ $name }}_up srv_is_up(logs_http_{{ $config.from }}/otel)
  http-request deny deny_status 503 unless backend_{{ $name }}_up
  {{- end }}
  {{- end }}
  default_backend healthcheck_backend

backend healthcheck_backend
  mode http
  server otel "$MY_POD_IP":13133
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
{{- if and (eq (include "sawmills-collector.siblingFallbackEnabled" $) "true") $to.fallback_endpoint (ne $mode "tcp") }}
  {{- $siblingEnabled = true }}
{{- end }}
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
  {{- if $siblingEnabled }}
  # Sibling fallback: detect forwarded requests to prevent routing loops (max 1 hop)
  acl is_sibling_hop hdr(X-Sibling-Hop) -m found
  use_backend logs_http_{{ $config.from }}_direct if is_sibling_hop
  {{- end }}
  default_backend logs_http_{{ $config.from }}

backend logs_http_{{ $config.from }}
  mode {{ if eq $mode "grpc" }}http{{ else }}{{ $mode }}{{ end }}
  {{- range $option := $config.backend_options }}
  option {{ $option }}
  {{- end }}
  {{- if not $config.backend_options }}
  {{- if not (eq $mode "grpc") }}
  option httpchk
  {{- end }}
  {{- end }}
  {{- with $fc }}
  {{- if .timeout }}
  {{ if .timeout.connect }}timeout connect {{ .timeout.connect }}{{- end }}
  {{ if .timeout.server }}timeout server {{ .timeout.server }}{{- end }}
  {{- end }}
  {{- end }}
  {{- if $to.fallback_endpoint }}
  {{- $server := $fc.server | default dict -}}
  {{- $interval := default 2000 $server.interval -}}
  {{- $rise := default 10 $server.rise -}}
  {{- $fall := default 1 $server.fall }}
  {{- if $siblingEnabled }}
  # Tag request as sibling-forwarded before sending to sibling tier
  http-request set-header X-Sibling-Hop 1
  {{- end }}
  server otel "$MY_POD_IP":{{ $to.port }} {{ $proto }} check port 13133 inter {{ $interval }} rise {{ $rise }} fall {{ $fall }} observe {{ if eq $mode "http" }}layer7{{ else }}layer4{{ end }} error-limit {{ $.Values.haproxy.error_limit }} on-error mark-down
  {{- if $siblingEnabled }}
  {{- $sf := $.Values.haproxy.sibling_fallback }}
  # Sibling tier: round-robin across other LB pods via headless service DNS
  # "backup" ensures these only activate when local otel is DOWN
  server-template sibling {{ $sf.max_servers | default 10 }} {{ include "sawmills-collector.lbHeadlessSvcFQDN" $ }}:{{ $config.from }} {{ $proto }} check port {{ $sf.check.port | default 13135 }} inter {{ $sf.check.interval | default 3000 }} rise {{ $sf.check.rise | default 2 }} fall {{ $sf.check.fall | default 2 }} backup resolvers k8s init-addr none
  # External fallback: last resort - weight 0 ensures all siblings are tried first
  server fallback {{ $to.fallback_endpoint }} {{ $proto }} backup weight 0 {{ if (or (not (hasKey $to "fallback_ssl")) $to.fallback_ssl) }}ssl verify none{{ end }}
  {{- else }}
  server fallback {{ $to.fallback_endpoint }} {{ $proto }} backup {{ if (or (not (hasKey $to "fallback_ssl")) $to.fallback_ssl) }}ssl verify none{{ end }}
  {{- end }}
  {{- else }}
  server otel "$MY_POD_IP":{{ $to.port }} {{ $proto }} check {{ if not (eq $mode "grpc") }}port 13133{{ end }}
  {{- end }}

{{- if $siblingEnabled }}
# Direct backend for sibling-forwarded requests (no sibling tier to prevent loops)
backend logs_http_{{ $config.from }}_direct
  mode {{ if eq $mode "grpc" }}http{{ else }}{{ $mode }}{{ end }}
  {{- range $option := $config.backend_options }}
  option {{ $option }}
  {{- end }}
  {{- if not $config.backend_options }}
  {{- if not (eq $mode "grpc") }}
  option httpchk
  {{- end }}
  {{- end }}
  # Strip sibling header before forwarding to local collector
  http-request del-header X-Sibling-Hop
  {{- $server := $fc.server | default dict -}}
  {{- $interval := default 2000 $server.interval -}}
  {{- $rise := default 10 $server.rise -}}
  {{- $fall := default 1 $server.fall }}
  server otel "$MY_POD_IP":{{ $to.port }} {{ $proto }} check port 13133 inter {{ $interval }} rise {{ $rise }} fall {{ $fall }} observe {{ if eq $mode "http" }}layer7{{ else }}layer4{{ end }} error-limit {{ $.Values.haproxy.error_limit }} on-error mark-down
  server fallback {{ $to.fallback_endpoint }} {{ $proto }} backup {{ if (or (not (hasKey $to "fallback_ssl")) $to.fallback_ssl) }}ssl verify none{{ end }}
{{- end }}
{{- end }}
{{- end -}} 