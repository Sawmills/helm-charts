# Sawmills Remote Operator Chart

This chart deploys the Sawmills Remote Operator, which maintains a bidirectional gRPC session with `controller.sawmills.ai` and optionally forwards Prometheus remote-write metrics. Use the values below to configure outbound connectivity.

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

## Managed Release RBAC Permissions

The namespace Role retains its historical `roles` and `rolebindings` grant. Each verb supports the managed release lifecycle:

* `create` installs the collector's feature Roles and RoleBindings and recreates objects during recovery.
* `get` reads existing named objects before Helm updates them.
* `patch` applies normal Helm upgrades and rollbacks.
* `update` supports replacement updates.
* `delete` removes obsolete objects and cleans up failed installations.
* `list` and `watch` remain necessary to restore historical Role grants during automatic rollback or compatibility recovery. Helm does not directly list or watch Roles, but Kubernetes refuses a Role update that grants permissions the caller no longer holds.

Removing `list` or `watch` would make an operator self-upgrade one-way: after narrowing its own Role, the operator could not restore an older revision with the historical grant. A reduction needs a separate owner-led migration with an out-of-band rollback path. This chart adds no permission and grants neither `bind` nor `escalate`.

The shipped collector chart conditionally creates namespace Roles and RoleBindings for EndpointSlice membership discovery and the worker CPU observer. Operator self-upgrades reconcile the operator's own RBAC. The manual chart grants no Role or RoleBinding operations. Four compatibility charts retain historical manifests to preserve their recovery contract.

Role names depend on configured release and workload names, so a fixed `resourceNames` list would reject supported releases. Kubernetes cannot restrict a top-level `create` request by `resourceNames`. All management grants remain namespace-scoped. Optional storage-class discovery requires a separate cluster permission owner; the namespace Role cannot manage cluster-scoped RBAC.

This audit covers all seven charts shipped here. The operator also accepts configured chart references and repository overrides; review external charts separately before selecting them. Regression tests lock the historical namespace grant and reject `bind`, `escalate`, and cluster-RBAC management resources.

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
