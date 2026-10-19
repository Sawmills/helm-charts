# Remote Operator Compatibility for Chart 0.163.0

This chart prepares an operator-only recovery upgrade from the public 0.163.0 chart to operator image 0.343.0. It preserves the legacy object names, selectors, Role, RoleBinding, ServiceAccount, Secret references, probes, resources and cache.

Declared changes are the image, the POD_UID field reference, the recovery label, a 14,400-second termination grace and the existing `/drain` preStop hook. Chart and application version labels identify the new package. The legacy five-character random rollout annotation remains unchanged in behavior.

This is a separate compatibility family. The chart uses fixed legacy RBAC names and ServiceAccount `sawmills-operator-sa`. It does not add new permissions or make modern RBAC controls effective.

## Configuration

Public values retain their 0.163.0 meanings:

- `replicaCount`: 3 by default.
- `apiKey`: empty by default. Prefer `apiKeyExistingSecret`, which selects an existing Secret with the fixed key `api-key`. Do not put credential values in shell commands or artifacts.
- `collectorName`: empty by default, used literally in the operator name.
- `image.pullPolicy`: `Always`. Its repository is fixed; the tag comes from Chart.AppVersion, 0.343.0. Values for `image.tag` and `image.repository` remain ignored.
- `operatorAddress`: `controller.sawmills.ai:443`.
- `grpcTrace`: empty by default; a nonempty value adds GRPC_TRACE.
- `cacheVolume.sizeLimit`: `500Mi`.
- `resources`: requests of 256Mi memory and 250m CPU; limits of 1Gi memory and 500m CPU.
- `securityContext`: the legacy values remain ignored. The template retains its fixed non-root container context.

Legacy `nameOverride` and `fullnameOverride` behavior also stays unchanged. Later-family scheduling, proxy, managed-chart, analytics, autoscaler, remote-write and configurable-RBAC values remain ignored. Do not use this package to enable them.

This synthetic example renders resources only:

```sh
helm template sawmills-remote-operator \
  helm-charts/sawmills-remote-operator-0163-compat \
  --namespace proof \
  --set apiKeyExistingSecret=synthetic-existing-secret \
  --set collectorName=synthetic-proof
```

## Validation and Release Limits

Tests compare complete rendered objects against `tests/operator-0.163.0.tgz`, SHA256 `783a2c46bac6a871f45645268c66fd7480c48cdce2daf5b12c16078ceaa645bd`. The public OCI baseline digest is `sha256:06de0e69c64dcc76c95226e5c75edf2de5d3c68f9750a71bf4384c7cbf78c4fe`.

Tests reuse the existing native Helm renderer and retained subprocess diagnostics. The existing compatibility CI entrypoint includes this family. Packages exclude tests, diagnostic receipts and the baseline archive.

Run on the devbox:

```sh
helm lint helm-charts/sawmills-remote-operator-0163-compat
python3 helm-charts/sawmills-remote-operator-compat/tests/test_compatibility.py
```

Publication, candidate digest binding, an owned staging upgrade and rollback proof, and customer eligibility remain separate approvals. Render tests establish none of those outcomes. No publication workflow or customer installation is included here.

After approval of a release packet, use its reviewed executor with the existing operator release name and namespace. Bind the installed chart, operator image, protected collector state and actual rollback revision first. Do not install over the collector release. A failed invariance check requires the packet's rollback and stop procedure. Missing telemetry remains UNKNOWN with its stated limits.
