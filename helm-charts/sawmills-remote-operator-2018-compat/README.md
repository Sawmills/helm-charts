# Remote Operator Compatibility for Chart 2.0.18

This package updates the operator while it preserves the public chart 2.0.18 contract. It targets operator image 0.343.0.

Resource names, selectors, RBAC, references, proxy handling, managed-chart values, scheduling, cache and resources stay unchanged. Its default memory limit remains 1Gi. Values for analytics Secret injection and the embedded autoscaler remain ignored, as in 2.0.18. Chart 2.0.23 compatibility has different behavior for these values and a 2Gi default memory limit.

Declared changes are the operator image, the POD_UID field reference, the recovery label, a 14,400-second termination grace and the preStop drain hook. The hook uses the existing `/drain` endpoint. An upgrade changes the operator release only. It does not authorize a collector deployment or a customer upgrade.

Render tests compare full objects against the pinned public archive in `tests/operator-2.0.18.tgz`. Its SHA256 is `2d6214e2d98e8b07f06564e166061d9f110f7f3e29f4a00aa6044f49c6413007`. The tests use synthetic settings and the existing compatibility renderer. Helm packages exclude the test archive and test files.

Before a customer upgrade, bind the published chart digest and the target operator image. Require an accepted owned staging upgrade and rollback proof. Capture the customer baseline and its native workload state. Preserve collector Pods, specifications, images, history, scaler bounds and reference bindings. Missing metric families remain UNKNOWN with explicit detection limits. A green render test does not establish live acceptance.

Run the focused checks on the devbox:

```sh
helm lint helm-charts/sawmills-remote-operator-2018-compat
python3 helm-charts/sawmills-remote-operator-2018-compat/tests/test_compatibility_2018.py
```

## Installation

This package requires a separate approved release packet. First bind its published digest and image to an accepted owned staging proof. Then use the reviewed executor with the existing operator release name and namespace. Reuse installed values and set the approved image tag explicitly. Retain the previous operator revision as the rollback target. Do not install this chart over the collector release.

## Configuration and Example

The supported settings are in `values.yaml`. They retain the 2.0.18 names and meanings. Use an existing Secret reference for credentials. Keep credential values out of shell arguments and saved examples.

The table lists every public value and its default. The image repository is `public.ecr.aws/s7a5m1b4/sawmills-remote-operator`. The pinned template retains its hard-coded container security context. The legacy `securityContext` values do not override it.

```text
┌────────────────────────────┬──────────────────────────────────┐
│ Setting                    │ Default                          │
├────────────────────────────┼──────────────────────────────────┤
│ replicaCount               │ 3                                │
│ rbac.createServiceAccount  │ true                             │
│ rbac.createRole            │ true                             │
│ rbac.createRoleBinding     │ true                             │
│ rbac.serviceAccountName    │ "sawmills-operator-sa"           │
│ rbac.roleName              │ "sawmills-role"                  │
│ rbac.roleBindingName       │ "sawmills-operator-rolebinding"  │
│ apiKey                     │ ""                               │
│ apiKeyExistingSecret       │ ""                               │
│ apiKeyExistingSecretKey    │ "api-key"                        │
│ collectorName              │ ""                               │
│ image.repository           │ Public ECR operator repository   │
│ image.pullPolicy           │ "Always"                         │
│ image.tag                  │ "0.343.0"                        │
│ operatorAddress            │ "https://controller.sawmills.ai" │
│ remoteWriteUrl             │ "https://ingress.sawmills.ai"    │
│ selfManaged                │ false                            │
│ proxy.http                 │ ""                               │
│ proxy.https                │ ""                               │
│ proxy.noProxy              │ []                               │
│ grpcTrace                  │ ""                               │
│ cacheVolume.sizeLimit      │ "500Mi"                          │
│ resources.requests.memory  │ "256Mi"                          │
│ resources.requests.cpu     │ "250m"                           │
│ resources.limits.memory    │ "1Gi"                            │
│ resources.limits.cpu       │ "500m"                           │
│ securityContext.runAsUser  │ 1000                             │
│ securityContext.runAsGroup │ 1000                             │
│ logLevel                   │ "info"                           │
│ affinity                   │ {}                               │
│ nodeSelector               │ {}                               │
│ tolerations                │ []                               │
│ managedChartsValues        │ {}                               │
│ managedCharts              │ {}                               │
│ managedChartsOverrides     │ {}                               │
└────────────────────────────┴──────────────────────────────────┘
```

This synthetic example renders resources without installing them:

```sh
helm template sawmills-remote-operator \
  helm-charts/sawmills-remote-operator-2018-compat \
  --namespace proof \
  --set apiKeyExistingSecret=synthetic-existing-secret \
  --set collectorName=synthetic-proof
```

## Troubleshooting

If rendering fails, retain the bounded error and compare the selected settings with the pinned 2.0.18 baseline. If readiness or native invariance fails after an approved upgrade, use the packet's bound operator rollback and stop. If a metric family is absent, report UNKNOWN with its detection limit. Do not infer zero loss from an empty result or repeat a consumed customer attempt.
