# Remote Operator Compatibility for Chart 2.0.18

This package updates the operator while it preserves the public chart 2.0.18 contract. It targets operator image 0.343.0.

Resource names, selectors, RBAC, references, proxy handling, managed-chart values, scheduling, cache and resources stay unchanged. The default memory limit remains 1Gi. Values for analytics Secret injection and the embedded autoscaler remain ignored, as in 2.0.18. The 2.0.23 compatibility package has different behavior for these values and a 2Gi default memory limit.

Declared changes are the operator image, the POD_UID field reference, the recovery label, a 14,400-second termination grace and the preStop drain hook. The hook uses the existing `/drain` endpoint. An upgrade changes the operator release only. It does not authorize a collector deployment or a customer upgrade.

Render tests compare full objects against the pinned public archive in `tests/operator-2.0.18.tgz`. Its SHA256 is `2d6214e2d98e8b07f06564e166061d9f110f7f3e29f4a00aa6044f49c6413007`. The tests use synthetic settings and the existing compatibility renderer. Helm packages exclude the test archive and test files.

Before a customer upgrade, bind the published chart digest and the target operator image. Require an accepted owned staging upgrade and rollback proof. Capture the customer baseline and its native workload state. Preserve collector Pods, specifications, images, history, scaler bounds and reference bindings. Missing metric families remain UNKNOWN with explicit detection limits. A green render test does not establish live acceptance.

Run the focused checks on the devbox:

```sh
helm lint helm-charts/sawmills-remote-operator-2018-compat
python3 helm-charts/sawmills-remote-operator-2018-compat/tests/test_compatibility_2018.py
```
