# Repository Guidelines for AI Agents

## Project Structure

```text
helm-charts/
├── helm-charts/
│   ├── sawmills-collector/      # Main collector chart
│   │   ├── templates/           # Kubernetes manifests
│   │   │   ├── _helpers.tpl     # Template helper functions
│   │   │   ├── _haproxy.tpl     # HAProxy config generation
│   │   │   ├── deployment.yaml  # Main deployment/daemonset
│   │   │   ├── load-balancer.yaml
│   │   │   ├── service.yaml
│   │   │   └── configmap.yaml
│   │   ├── tests/               # Helm unit tests
│   │   ├── values.yaml          # Default configuration
│   │   └── README.md            # Chart documentation
│   └── sawmills-remote-operator/
├── .github/workflows/           # CI pipelines
├── .trunk/                      # Trunk linting config
└── scripts/                     # Utility scripts
```

## Build, Lint & Test Commands

### Linting

```bash
# Helm lint (required before PR)
helm lint helm-charts/sawmills-collector

# Trunk check (comprehensive linting)
trunk check

# Specific file check
trunk check path/to/file.yaml
```

### Template Validation

```bash
# Basic template render
helm template test-release helm-charts/sawmills-collector

# With specific values
helm template test helm-charts/sawmills-collector \
  --set haproxy.enabled=true \
  --set haproxy.tls.secretName=my-secret

# Debug mode for troubleshooting
helm template test-release helm-charts/sawmills-collector --debug
```

### Unit Tests

```bash
# Run all tests
cd helm-charts/sawmills-collector && ./tests/run-tests.sh

# Run specific test file
helm unittest helm-charts/sawmills-collector -f 'tests/deployment_affinity_test.yaml'

# Run with color output
helm unittest helm-charts/sawmills-collector --color
```

### Local Testing (Orbstack/Kind)

```bash
# Dry run install
helm install test-release helm-charts/sawmills-collector --dry-run --debug

# Install to namespace
helm install sawmills-collector helm-charts/sawmills-collector -n sawmills --create-namespace

# Upgrade with existing values
helm upgrade sawmills-collector helm-charts/sawmills-collector -n sawmills --reuse-values

# Check pod status
kubectl get pods -n sawmills -l app.kubernetes.io/instance=sawmills-collector
```

## Helm Template Coding Style

### Helper Function Naming

```yaml
# Use chart name prefix, descriptive kebab-case names
{{- define "sawmills-collector.fullname" -}}
{{- define "sawmills-collector.labels" -}}
{{- define "sawmills-collector.haproxyTlsEnabled" -}}
```

### Template Context

```yaml
# Use '.' for template context consistently (NOT '$')
{{- if eq (include "sawmills-collector.haproxyTlsEnabled" .) "true" }}

# Inside range loops, use '$' to access root context
{{- range $name, $config := .Values.haproxy.mapping }}
  {{- $mode := $config.to.mode | default "http" }}
  {{- /* Access root values with $ */ -}}
  {{- $.Values.haproxy.tls.certPath }}
{{- end }}
```

### Conditional Blocks

```yaml
# Always use explicit boolean checks for helpers returning strings
{{- if eq (include "sawmills-collector.haproxyTlsEnabled" .) "true" }}

# For direct value checks, use truthy evaluation
{{- if .Values.haproxy.enabled }}
{{- if and .Values.haproxy.enabled (not .Values.loadBalancer.enabled) }}
```

### Indentation & Formatting

```yaml
# Use nindent for proper YAML indentation
labels:
  {{- include "sawmills-collector.labels" . | nindent 4 }}

# Whitespace control: use {{- and -}} to trim
{{- if .Values.feature.enabled }}
  value: {{ .Values.feature.value }}
{{- end }}
```

### Value Defaults

```yaml
# Use 'default' for fallback values
{{ $mode := $config.to.mode | default "http" }}
{{ $timeout := .Values.timeout | default "5s" }}

# Use 'required' for mandatory values
{{ required "haproxy.tls.secretName is required when TLS is enabled" .Values.haproxy.tls.secretName }}
```

### Comments

```yaml
{{/*
Helper function description.
Returns "true" or "false" as string for consistent comparison.
*/}}
{{- define "sawmills-collector.haproxyTlsEnabled" -}}
```

## values.yaml Conventions

### Structure

```yaml
# Group related settings with descriptive comments
haproxy:
  enabled: false
  image: public.ecr.aws/docker/library/haproxy:3.1
  
  # TLS configuration for HAProxy sidecar
  tls:
    secretName: ""       # Name of existing K8s TLS secret
    certificate: ""      # Base64-encoded certificate (alternative)
    privateKey: ""       # Base64-encoded key (alternative)
    certPath: "/etc/haproxy/certs"
```

### Naming

* Use camelCase for value keys: `secretName`, `certPath`
* Use snake\_case for config that maps to external systems: `s3_bucket`, `api_key`
* Boolean flags: `enabled`, `disableLimits`

## Commit & PR Guidelines

### Commit Messages

```text
feat(sawmills-collector): add TLS termination support for HAProxy
fix(sawmills-collector): use ALPN h2 for TLS gRPC binds
refactor(sawmills-collector): use crt-store instead of init container
docs(sawmills-collector): add HAProxy version requirement note
```

### PR Checklist

* \[ ] `helm lint` passes
* \[ ] `helm template` renders correctly
* \[ ] Unit tests pass (`./tests/run-tests.sh`)
* \[ ] Test with different configurations (HAProxy, KEDA, DaemonSet, LoadBalancer)
* \[ ] Update README.md if adding new features
* \[ ] No breaking changes to existing values.yaml structure

### Version Labels

* `version:major` - Breaking changes
* `version:minor` - New features, backward compatible
* `version:patch` - Bug fixes (default)

## HAProxy-Specific Guidelines

### TLS Configuration

```yaml
# HAProxy 3.0+ required for crt-store directive
crt-store k8s-tls
  crt-base {{ .Values.haproxy.tls.certPath }}/
  key-base {{ .Values.haproxy.tls.certPath }}/
  load crt "tls.crt" key "tls.key" alias "haproxy-cert"

# TLS bind uses crt-store reference
bind *:{{ $port }} ssl crt @k8s-tls/haproxy-cert

# For gRPC over TLS, use ALPN (not proto h2)
bind *:{{ $port }} ssl crt @k8s-tls/haproxy-cert alpn h2

# For cleartext HTTP/2 (h2c), use proto h2
bind *:{{ $port }} proto h2
```

## Testing Configurations

Always test these variations before PR:

```bash
# HAProxy enabled
helm template test . --set haproxy.enabled=true

# HAProxy with TLS
helm template test . --set haproxy.enabled=true --set haproxy.tls.secretName=test

# KEDA autoscaling
helm template test . --set keda.enabled=true

# DaemonSet mode
helm template test . --set mode=daemonSet

# LoadBalancer mode
helm template test . --set loadBalancer.enabled=true
```

## Stable Service Contracts

* Treat `{{ fullname }}-headless` in `sawmills-collector` LoadBalancer mode as an external compatibility contract, not an internal implementation detail.
* Do not rename, remove, or retarget that Service without an explicit migration plan and a clearly marked breaking-change review.
* If a PR touches headless Service naming or sibling-fallback DNS, add or update regression tests that lock the stable service name in place.

## CI Checks

PR checks that must pass:

1. `check-codeowners / build` - CODEOWNERS validation
2. `Helm Chart Tests / Test Helm Chart` - Lint, template, unit tests

Bot reviews (informational):

* Baz Reviewer
* cubic AI code reviewer
* CodeRabbit

## Platform Context

For overall architecture, service dependencies, data flows, and cross-cutting concerns, read the `sawmills-platform` skill.
