# Sawmills Remote Operator Manual Chart

This chart deploys the Sawmills Remote Operator for environments where collectors are deployed manually. It aligns with the existing product-level `selfManaged` mode in `collectors` and `frontend`:

* the chart defaults `selfManaged=true`
* pipeline changes generate a Helm command for the customer to run manually
* the remote operator does not get RBAC to install, upgrade, list, or uninstall the collector chart
* autoscaling must stay outside the remote operator in this mode

The manual Role is narrowed to the runtime paths that still exist in this mode:

* startup bookkeeping plus hot reload / Live Tail session writes via `ConfigMap`
* deployment status sampling via `Pods` + collector `Service` lookups

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
Any non-default `autoscaler.*` value will fail rendering.

## Pin Images By Digest

Set `image.digest` to render the operator image as `repository@digest` instead of `repository:tag`:

```yaml
image:
  repository: public.ecr.aws/s7a5m1b4/sawmills-remote-operator
  digest: sha256:...
```

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

## Pod Security Defaults

| Value | Default | Purpose |
| --- | --- | --- |
| `podSecurityContext.runAsNonRoot` | `true` | Require non-root containers without a container-level override. |
| `podSecurityContext.seccompProfile.type` | `RuntimeDefault` | Use the container runtime's default system-call filter. |

Pods use `podSecurityContext.runAsNonRoot: true` and `podSecurityContext.seccompProfile.type: RuntimeDefault` by default. Existing container security settings take precedence. The chart does not add pod UID, GID or volume-group defaults.

pod runAsNonRoot is now true by default; a custom root sidecar must set its own runAsUser or the release fails to start

Use a non-zero numeric `securityContext.runAsUser` for a custom sidecar, or an image with a numeric non-root `USER`. Recheck this requirement when you override an image or container security settings.

Set `podSecurityContext.runAsNonRoot: false` only for a reviewed security exception. This override remains a scan finding. Existing container contexts still enforce their own settings.

## Optional Egress NetworkPolicy

`networkPolicy.enabled` defaults to `false`. Enable it with an explicit `networkPolicy.egress` list to restrict outbound traffic for this release. An enabled policy with no rules denies all egress. Inbound traffic is unchanged by this policy.

See [NetworkPolicy configuration](../../docs/network-policy.md) for required destinations, DNS and Kubernetes API rules, and cluster-specific limits. No internet, API, or DNS allowance is added automatically.

## Read-Only Operator Filesystem

The operator uses a read-only container root filesystem by default. Writable emptyDir volumes keep its state at `/cache`, temporary files at `/tmp`, and Helm files at `/helm`. These files disappear when the Pod is replaced.

| Value | Default | Purpose |
| --- | --- | --- |
| `securityContext.readOnlyRootFilesystem` | `true` | Keep the image filesystem read-only. |
| `tmpVolume.sizeLimit` | `500Mi` | Bound temporary files and the Go Helm client's repository files. |
| `helmVolume.sizeLimit` | `500Mi` | Bound Helm CLI cache, configuration and data. |

`TMPDIR=/tmp`, `KUBECACHEDIR=/tmp/.kube/cache`, `HELM_CACHE_HOME=/helm/cache`, `HELM_CONFIG_HOME=/helm/config` and `HELM_DATA_HOME=/helm/data` point into writable volumes. The Go Helm client also writes `/tmp/.helmrepo` and `/tmp/.helmcache`; Helm environment variables do not redirect those SDK defaults. Kubernetes discovery also uses the temporary volume through `KUBECACHEDIR`.

Container UID/GID 10001 and existing security settings remain unchanged. Set `securityContext.readOnlyRootFilesystem: false` only for a reviewed security exception. This opt-out remains a scan finding.

Staging install, upgrade and rollback acceptance remains pending. Rendering and client dry runs do not establish runtime write access or successful operator operations.

### Upgrade Existing Manual Releases

Older manual-chart defaults set `securityContext.readOnlyRootFilesystem: false`. An upgrade with `--reuse-values` retains that old value. To enable the read-only root, pass the setting explicitly:

```bash
helm upgrade <release> <new-chart> --reuse-values \
  --set securityContext.readOnlyRootFilesystem=true
```

Verify the running container setting after upgrade. Retaining `false` is a security exception, even if it came from the old defaults. The staging upgrade proof must include the explicit flag and a rendered/running value check.
