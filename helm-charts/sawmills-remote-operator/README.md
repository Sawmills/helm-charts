# Sawmills Remote Operator Chart

This chart deploys the Sawmills Remote Operator, which maintains a bidirectional gRPC session with `controller.sawmills.ai` and optionally forwards Prometheus remote-write metrics. Use the values below to configure outbound connectivity.

## API Key Configuration

Set `apiKeyExistingSecret` to the name of an existing Secret. Its key defaults to `api-key`; use `apiKeyExistingSecretKey` to select another key.
The existing Secret takes precedence over the deprecated inline `apiKey` value, and the chart does not create a Secret on this path.
If `apiKeyExistingSecret` is empty, the chart requires a non-empty `apiKey` and refuses to render without it. Avoid storing real credentials in values files or rendered manifests.

## Storage Class Discovery Permissions

Set `rbac.storageClassDiscovery.enabled=true` to add a separate ClusterRole and ClusterRoleBinding for storage class discovery.
The only cluster permission is `get` and `list` on `storage.k8s.io/storageclasses`.
The binding selects `rbac.serviceAccountName` in the release namespace.
The namespace Role keeps its current permissions.

The cluster objects use `<namespace>.<release>-storageclasses` names.
Storage class discovery defaults to false so namespace-only installations retain their current permissions.
The existing `rbac.createRole` and `rbac.createRoleBinding` values control only the namespace objects.

A cluster permission owner must install this grant.
An operator with only namespace permissions cannot grant cluster access to itself.
Publishing the chart alone does not update customer permissions.

## Collector Membership Permissions

The namespace Role grants `discovery.k8s.io/endpointslices` `list` and `watch`. Operators need these permissions before they can create the collector's membership-discovery Role. This chart adds no `bind` or `escalate` permission.

A cluster permission owner must approve and install this grant. An existing operator without these permissions cannot grant them to itself. Publishing this chart does not update customer clusters or enable collector membership discovery.

## Pin Images By Digest

Set `image.digest` to render the operator image as `repository@digest` instead of `repository:tag`:

```yaml
image:
  repository: public.ecr.aws/s7a5m1b4/sawmills-remote-operator
  digest: sha256:...
```

## Outbound proxy support

Customers that require all internet-bound traffic to pass through an HTTP/HTTPS proxy can set the new `proxy` block. The chart wires these values into the `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` environment variables consumed by the operator so TLS sessions still terminate at `controller.sawmills.ai`.

```yaml
proxy:
  http: http://user:pass@corp-proxy.example.com:32281
  https: http://user:pass@corp-proxy.example.com:32281
  noProxy:
    - 10.0.0.0/8
```

If either proxy.http or proxy.https is set, the chart will automatically populate NO\_PROXY with the following predefined values:

* `localhost`, `127.0.0.1`, `::1`, `kubernetes`, `kubernetes.default.svc`, `.svc`, `.svc.cluster.local`, `.cluster.local`,
* `$(KUBERNETES_SERVICE_HOST)` and `$(POD_IP)`

Use `noProxy` to extend that list with any additional domains or CIDRs that must bypass your proxy.

You can also set them via the CLI:

```bash
helm upgrade --install remote-operator ./helm-charts/sawmills-remote-operator \
  --set proxy.https="http://$USER:$HOSTNAME@bar.proxy.square:32281" \
  --set proxy.http="http://$USER:$HOSTNAME@bar.proxy.square:32281" \
  --set proxy.noProxy[0]="kubernetes.default.svc" \
  --set proxy.noProxy[1]="10.0.0.0/8"
```

When the values are empty (default), the operator connects directly without a proxy. Internal cluster calls (for example, Kubernetes API access) continue to bypass the proxy regardless of these settings.

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
    image:
      digest: sha256:...
    haproxy:
      image:
        digest: sha256:...

managedChartsOverrides:
  sawmills-collector:
    chartName: oci://registry.example.com/sawmills-collector
    version: 1.2.3
```
