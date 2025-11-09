# Sawmills Remote Operator Chart

This chart deploys the Sawmills Remote Operator, which maintains a bidirectional gRPC session with `controller.sawmills.ai` and optionally forwards Prometheus remote-write metrics. Use the values below to configure outbound connectivity.

## Outbound proxy support

Customers that require all internet-bound traffic to pass through an HTTP/HTTPS proxy can set the new `proxy` block. The chart wires these values into the `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` environment variables consumed by the operator so TLS sessions still terminate at `controller.sawmills.ai`.

```yaml
proxy:
  http: http://user:pass@corp-proxy.example.com:32281
  https: http://user:pass@corp-proxy.example.com:32281
  noProxy:
    - kubernetes.default.svc
    - 10.0.0.0/8
```

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
