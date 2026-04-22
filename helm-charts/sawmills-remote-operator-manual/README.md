# Sawmills Remote Operator Manual Chart

This chart deploys the Sawmills Remote Operator for environments where collectors are deployed manually. It aligns with the existing product-level `selfManaged` mode in `collectors` and `frontend`:

* the chart defaults `selfManaged=true`
* pipeline changes generate a Helm command for the customer to run manually
* the remote operator does not get RBAC to install, upgrade, list, or uninstall the collector chart

The manual Role is narrowed to the runtime paths that still exist in this mode:

* startup bookkeeping plus hot reload / Live Tail session writes via `ConfigMap`
* deployment status sampling via `Pods` + collector `Service` lookups
* optional embedded autoscaler access to `HorizontalPodAutoscaler` + `Lease`

Permissions that are not part of the manual-deployment path were removed from this chart, including all collector-chart Helm lifecycle resources, `events`, `pods/log`, `pods/metrics`, `jobs`, `podmonitors`, `rbac.authorization.k8s.io/*`, and `opentelemetry.io/*`.

The chart keeps `configmaps.patch` because both hot reload and Live Tail write session/update state into mounted ConfigMaps. It does not grant `pods.patch`; the current repos only write pod annotations as a follow-up `kubectl annotate`, and no reader for those annotation keys was found.

## Install

```bash
helm upgrade --install sawmills-remote-operator \
  oci://public.ecr.aws/s7a5m1b4/sawmills-remote-operator-manual-chart \
  --version 0.1.0 \
  --create-namespace \
  --namespace sawmills \
  --set apiKeyExistingSecret=sawmills-secret \
  --set operatorAddress=https://controller.sawmills.ai \
  --set collectorName="my-collector"
```

All existing values from the standard remote-operator chart remain available. This chart is intended for manual deployment flows only.
It defaults the operator to `SELF_MANAGED=true`.
`collectorName` is required.

## Outbound proxy support

Customers that require all internet-bound traffic to pass through an HTTP/HTTPS proxy can set the `proxy` block. The chart wires these values into the `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` environment variables consumed by the operator so TLS sessions still terminate at `controller.sawmills.ai`.

If your proxy URL includes credentials, do not put `http://user:pass@...` directly in `values.yaml`. Use `proxy.existingSecret` instead so the credentials stay in a Kubernetes `Secret` instead of the Deployment manifest and Helm release history.

```yaml
proxy:
  existingSecret: corp-proxy-secret
  existingSecretHttpKey: proxy-http
  existingSecretHttpsKey: proxy-ssl
  noProxy:
    - 10.0.0.0/8
```

If either proxy.http or proxy.https is set, the chart will automatically populate NO\_PROXY with the following predefined values:

* `localhost`, `127.0.0.1`, `::1`, `kubernetes`, `kubernetes.default.svc`, `.svc`, `.svc.cluster.local`, `.cluster.local`,
* `$(KUBERNETES_SERVICE_HOST)` and `$(POD_IP)`

Use `noProxy` to extend that list with any additional domains or CIDRs that must bypass your proxy.

You can also set them via the CLI:

```bash
helm upgrade --install remote-operator ./helm-charts/sawmills-remote-operator-manual \
  --set proxy.http="http://proxy.internal:32281" \
  --set proxy.https="http://proxy.internal:32281" \
  --set proxy.noProxy[0]="kubernetes.default.svc" \
  --set proxy.noProxy[1]="10.0.0.0/8"
```

When the values are empty (default), the operator connects directly without a proxy. Internal cluster calls (for example, Kubernetes API access) continue to bypass the proxy regardless of these settings.

If you need authenticated proxies, create a `Secret` that contains the full URLs:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: corp-proxy-secret
type: Opaque
stringData:
  proxy-http: http://user:pass@corp-proxy.example.com:32281
  proxy-ssl: http://user:pass@corp-proxy.example.com:32281
```

## Embedded autoscaler

Configure the embedded autoscaler through the chart values below.
Backward-compatible behavior:

* `autoscaler.enabled=true` emits `AUTOSCALER_ENABLED=true`.
* Other autoscaler fields are optional overrides and are emitted only when `autoscaler.enabled=true`.
* When optional values are `null`, the chart does not emit the matching env var, so operator defaults remain in effect.

```yaml
autoscaler:
  enabled: false
  dryRun: null
  metricsEndpoint: null
  otlpMetricsEndpoint: null
  targetHPAName: null
  leaseName: null
  labelSelectors: null
  memoryLimitBytes: null
  globalMinReplicas: null
  globalMaxReplicas: null
```

Set non-null values only for knobs you want to override from chart values.
Use `autoscaler.otlpMetricsEndpoint` to emit `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` explicitly for OTel metric export.

## Additional references

* `values.yaml` – full list of configurable settings
* `templates/deployment.yaml` – environment variables injected into the operator Pod
* `templates/sawmills-role.yaml` – reduced Kubernetes permissions for manual-only deployments
* `test/local-test/README.md` in the `remote-operator` repository – manual steps for validating proxy mode locally

## Managed chart overrides

The operator now accepts two JSON payloads:

* `MANAGED_CHARTS_VALUES` (`managedChartsValues` in `values.yaml`, legacy alias: `managedCharts`) supplies per-release values that get merged into the child chart.
* `MANAGED_CHARTS` (`managedChartsOverrides` in `values.yaml`) lets you override the chart reference and/or version for a managed release.

Example:

```yaml
managedChartsValues:
  sawmills-collector:
    replicaCount: 2

managedChartsOverrides:
  sawmills-collector:
    chartName: oci://registry.example.com/sawmills-collector
    version: 1.2.3
```
