# Remote Operator Compatibility Chart

This chart upgrades installations based on operator chart 2.0.5 to image 0.342.0.
It preserves the old image.tag and Helm tpl behavior for collectorName and managedCharts.
The standard operator chart remains separate.

Baseline templates come from the published sawmills-remote-operator-chart 2.0.5 archive.
Its SHA-256 is `99c3de228f30dec88a479918a67058d34ceea5822b7a38e96c61ee032488fbb3`.
The public render test retains that archive as its comparison baseline.

The changes add POD_UID, the health-aware recovery label, a 14,400-second termination grace,
and the operator drain hook. Legacy Deployment names and selectors remain stable even
though this chart has a separate package name. Existing Role rules, service accounts,
bindings, Secret references, scheduling, resources, cache, and managed values retain their
2.0.5 templates. No new permission is required by this chart.

Operator 0.342.0 receives `REMOTE_WRITE_URL` from this chart for its status metrics.
Its `remoteWriteUrl` value defaults to `https://ingress.sawmills.ai`, as in the standard
operator chart. The template retains that fallback when `--reuse-values` supplies old
values without the new field. An empty URL otherwise causes a send error on each status report.
For Sawmills staging, set `remoteWriteUrl=https://ingress.sawmills-staging.com`.

Use the existing release name and namespace. Preserve release values inside the cluster
with `--reuse-values`, and explicitly set `image.tag=0.342.0`: reused values can retain
the old image tag. Bind the immutable chart version and digest before an upgrade.
The image version comes from image.tag, independently of the chart version.

A remote Helm command can replace its own operator pod before completion. Use a reviewed
executor that survives that replacement, and inspect both Helm state and all manager
instances afterward. Record the previous successful revision and an independent rollback
route first. A timeout or lost connection requires reconciliation of that same operation.

Operator 0.342.0 exits after its drain hook completes and fixes remote-write URL handling.
The older 0.340.0 process can remain connected until its four-hour termination grace ends.
Pod readiness alone does not prove that old instances retired. Customer use requires
the separate staging upgrade and rollback proof, preserved settings, and explicit approval.

Run the public render regression with Python 3, PyYAML 6.0.3, and Helm 3.18:

```sh
python3 helm-charts/sawmills-remote-operator-compat/tests/test_compatibility.py
```

The test compares complete rendered objects, including templated values, custom identities,
RBAC, existing Secret references, and scheduling. It permits only the declared recovery
fields, target image, remote-write URL, and chart version labels to change.

## Prerequisites and Upgrade Example

Use Helm with OCI digest-reference support and access to the existing release namespace
and its existing service account. The Helm 3.15.3 bundled with operator 0.340.0 rejects
the direct digest reference below. Do not run this example with that bundled Helm.
Obtain the approved executor route, settled release revision, and rollback binding first.
Run this synthetic example only through that executor after approval:
Set BOUND_CHART_DIGEST to the approved published manifest digest, including sha256:.
The executor must pass the resulting literal chart reference to Helm.

```sh
helm upgrade sawmills-remote-operator \
  "oci://public.ecr.aws/s7a5m1b4/sawmills-remote-operator-compat-chart@${BOUND_CHART_DIGEST:?Bind the approved chart digest first}" \
  --namespace example-namespace \
  --reuse-values --set-string image.tag=0.342.0 \
  --wait --timeout 10m
```

For a new isolated test installation, use helm install with a nonsecret values file
that references an existing API-key Secret. Set the RBAC creation switches to false
when reusing existing identities. Customer upgrades preserve their existing values.

## Compatibility Chart Defaults

These values retain the legacy configuration contract. This chart defaults image.tag
to 0.342.0; the original 2.0.5 archive defaults it to 0.176.0.

```text
┌───────────────────────────────┬─────────────────────────────────┐
│ Value                         │ Default                         │
├───────────────────────────────┼─────────────────────────────────┤
│ replicaCount                  │ 3                               │
│ rbac.createServiceAccount     │ true                            │
│ rbac.createRole               │ true                            │
│ rbac.createRoleBinding        │ true                            │
│ rbac.serviceAccountName       │ sawmills-operator-sa            │
│ rbac.roleName                 │ sawmills-role                   │
│ rbac.roleBindingName          │ sawmills-operator-rolebinding   │
│ apiKey                        │ empty (deprecated)              │
│ apiKeyExistingSecret          │ empty                           │
│ apiKeyExistingSecretKey       │ api-key                         │
│ collectorName                 │ empty                           │
│ image.pullPolicy              │ Always                          │
│ image.tag                     │ 0.342.0                         │
│ operatorAddress               │ https://controller.sawmills.ai  │
│ remoteWriteUrl                │ https://ingress.sawmills.ai     │
│ grpcTrace                     │ empty                           │
│ cacheVolume.sizeLimit         │ 500Mi                           │
│ resources.requests.memory     │ 256Mi                           │
│ resources.requests.cpu        │ 250m                            │
│ resources.limits.memory       │ 1Gi                             │
│ resources.limits.cpu          │ 500m                            │
│ securityContext.runAsUser     │ 1000 (legacy value)             │
│ securityContext.runAsGroup    │ 1000 (legacy value)             │
│ logLevel                      │ info                            │
│ affinity                      │ {}                              │
│ nodeSelector                  │ {}                              │
│ tolerations                   │ []                              │
│ managedCharts                 │ sawmills-collector: null        │
└───────────────────────────────┴─────────────────────────────────┘
```

Legacy templates fix the container UID and GID at 10001, despite the retained
securityContext values. Optional nameOverride and fullnameOverride values preserve
custom resource names. The collectorName and managedCharts values support Helm tpl.

## Troubleshooting

When old instances remain connected, stop promotion and retain the operation identity.
A lost command stream does not establish Helm failure. Inspect the same release revision
and executor exit status before any action. On a failed health gate, use the bound
rollback route. Do not export release values or change RBAC to clear an upgrade error.
