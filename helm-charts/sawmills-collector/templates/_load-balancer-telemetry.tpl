{{/*
Render the LB telemetry container once for either sibling or native sidecar placement.
The native sidecar keeps serving main's final meter export until main stops.
*/}}
{{- define "sawmills-collector.loadBalancerTelemetryContainer" -}}
{{- $lbTelemetryOtelConfig := default dict .Values.loadBalancer.telemetryOtelConfig }}
{{- $lbTelemetryOtelS3Path := default "" $lbTelemetryOtelConfig.s3path }}
{{- $lbTelemetryOtelEncryptionKey := default "" $lbTelemetryOtelConfig.encryptionKey }}
{{- $lbTelemetryCaBundle := include "sawmills-collector.loadBalancerTelemetryCaBundle" . }}
{{- $lbPressureReadinessEnabled := and .Values.loadBalancer.enabled (.Values.loadBalancer.pressureReadiness | default dict).enabled -}}
- name: telemetry-collector
  {{- if .Values.loadBalancer.telemetryNativeSidecar }}
  restartPolicy: Always
  lifecycle:
    preStop:
      exec:
        command: [/bin/sleep, {{ .Values.rollout.telemetry.preStopSleepSeconds | quote }}]
  {{- end }}
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  image: {{ include "sawmills-collector.image" . }}
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  {{- if or $lbTelemetryOtelS3Path .Values.kedaScaler.enabled }}
  args:
    {{- if $lbTelemetryOtelS3Path }}
    - "--config={{ $lbTelemetryOtelS3Path }}{{- if $lbTelemetryOtelEncryptionKey }}@{{ $lbTelemetryOtelEncryptionKey }}{{- end }}"
    {{- else }}
    - "--config=file:/etc/otel/config.yaml"
    {{- end }}
    {{- if .Values.kedaScaler.enabled }}
    - "--config=file:/etc/otel/keda.yaml"
    {{- end }}
  {{- end }}
  env:
    - name: MY_POD_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    - name: MY_POD_IP
      valueFrom:
        fieldRef:
          fieldPath: status.podIP
    {{- if .Values.kedaScaler.enabled }}
    - name: KEDA_SCALER_OTLP_RECEIVER_PORT
      value: {{ .Values.kedaScaler.service.otlpReceiverPort | quote }}
    - name: KEDA_SCALER_OTEL_PROMETHEUS_PORT
      value: {{ .Values.kedaScaler.service.otelPrometheusPort | quote }}
    {{- end }}
    - name: COLLECTOR_NAME
      value: {{ .Values.collectorName }}
    - name: COLLECTOR_ID
      value: {{ .Values.collectorId }}
    - name: PROMETHEUS_PORT
      value: {{ .Values.telemetry.prometheus.port | quote }}
    {{- if .Values.telemetry.pprof.enabled }}
    - name: TELEMETRY_PPROF_PORT
      value: {{ .Values.telemetry.pprof.port | default 1778 | quote }}
    {{- end }}
    {{- if $lbPressureReadinessEnabled }}
    - name: PRESSURE_PROMETHEUS_PORT
      value: {{ .Values.telemetry.pressurePrometheus.port | default 19466 | quote }}
    {{- end }}
    - name: PROMETHEUS_REMOTE_WRITE_ENDPOINT
      value: {{ .Values.prometheusremotewrite.endpoint }}
    - name: PROMETHEUS_REMOTE_WRITE_API_KEY
      valueFrom:
        secretKeyRef:
          {{- include "sawmills-collector.secretConfig" . | nindent 10 }}
    - name: COLLECTOR_GATEWAY_ENDPOINT
      value: {{ .Values.collector_gateway.endpoint }}
    - name: COLLECTOR_GATEWAY_API_KEY
      valueFrom:
        secretKeyRef:
          {{- include "sawmills-collector.secretConfig" . | nindent 10 }}
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
      {{- if $noProxy }}
      value: {{ printf "%s,$(MY_POD_IP)" $noProxy | quote }}
      {{- else }}
      value: "$(MY_POD_IP)"
      {{- end }}
    {{- end }}
    {{- if .Values.telemetryExtraEnv }}
    {{- toYaml .Values.telemetryExtraEnv | nindent 4 }}
    {{- end }}
  ports:
    - name: prometheus
      containerPort: {{ .Values.telemetry.prometheus.port }}
      protocol: TCP
    {{- if .Values.telemetry.pprof.enabled }}
    - name: telemetry-pprof
      containerPort: {{ .Values.telemetry.pprof.port | default 1778 }}
      protocol: TCP
    {{- end }}
    {{- if $lbPressureReadinessEnabled }}
    - name: pressure-prom
      containerPort: {{ .Values.telemetry.pressurePrometheus.port | default 19466 }}
      protocol: TCP
    {{- end }}
    - name: ro-otlp-http
      containerPort: {{ .Values.telemetry.remoteOperatorOtlpHttpPort | default 14319 }}
      protocol: TCP
  livenessProbe:
    # SAW-10798: probe the Prometheus metrics endpoint, not the always-up
    # health_check handler (13134). The metrics endpoint goes unresponsive
    # when the exporter wedges under GC thrash, so a wedged sidecar now
    # fails liveness and Kubernetes restarts it instead of running forever.
    httpGet:
      path: {{ .Values.rollout.telemetry.probes.liveness.path | default "/metrics" }}
      port: {{ .Values.rollout.telemetry.probes.liveness.port | default .Values.telemetry.prometheus.port }}
    initialDelaySeconds: {{ .Values.rollout.telemetry.probes.liveness.initialDelaySeconds }}
    periodSeconds: {{ .Values.rollout.telemetry.probes.liveness.periodSeconds }}
    failureThreshold: {{ .Values.rollout.telemetry.probes.liveness.failureThreshold }}
  resources:
    {{- if .Values.telemetry.resources.requests }}
    requests:
      {{- toYaml .Values.telemetry.resources.requests | nindent 6 }}
    {{- end }}
    {{- if not .Values.telemetry.resources.disableLimits }}
    limits:
      {{- toYaml .Values.telemetry.resources.limits | nindent 6 }}
    {{- end }}
  volumeMounts:
    {{- if not $lbTelemetryOtelS3Path }}
    - name: sawmills-load-balancer-telemetry-config
      mountPath: /etc/otel/config.yaml
      subPath: telemetry-config.yaml
    {{- end }}
    {{- if $lbTelemetryCaBundle }}
    - name: sawmills-telemetry-trust
      mountPath: /etc/otel/certs/ca-cert.pem
      subPath: ca-cert.pem
      readOnly: true
    {{- end }}
    {{- if .Values.kedaScaler.enabled }}
    - name: sawmills-telemetry-keda-config
      mountPath: /etc/otel/keda.yaml
      subPath: keda.yaml
    {{- end }}
    - name: tmp
      mountPath: /tmp
{{- end }}
