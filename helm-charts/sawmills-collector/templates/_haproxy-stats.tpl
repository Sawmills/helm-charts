{{/* Select the externally managed Secret, otherwise the stable per-release name. */}}
{{- define "sawmills-collector.haproxyStatsSecretName" -}}
{{- .Values.haproxy.stats.existingSecret | default (printf "%s-haproxy-stats" (include "sawmills-collector.fullname" .)) -}}
{{- end -}}

{{/* Secret data is generated only here, never in values or the ConfigMap. */}}
{{- define "sawmills-collector.haproxyStatsAuth" -}}
{{- $name := include "sawmills-collector.haproxyStatsSecretName" . -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace $name -}}
{{- if $secret -}}
{{- required "existing HAProxy stats Secret must contain data.auth" (dig "data" "auth" "" $secret) -}}
{{- else -}}
{{- printf "stats:%s" (randAlphaNum 32) | b64enc -}}
{{- end -}}
{{- end -}}
