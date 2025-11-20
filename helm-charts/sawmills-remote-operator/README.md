# Sawmills Remote Operator Chart

This chart deploys the Sawmills Remote Operator, which maintains a bidirectional gRPC session with `controller.sawmills.ai` and optionally forwards Prometheus remote-write metrics. Use the values below to configure outbound connectivity.

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

managedChartsOverrides:
  sawmills-collector:
    chartName: oci://registry.example.com/sawmills-collector
    version: 1.2.3
```
