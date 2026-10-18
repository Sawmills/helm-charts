# Remote Operator Compatibility for Chart 2.0.23

This chart upgrades an installation from public operator chart 2.0.23 while preserving its resource names, selectors, values behavior and references. It is separate from the compatibility chart for 2.0.5. Customer use requires an approved execution plan and a published artifact digest.

The baseline is `oci://public.ecr.aws/s7a5m1b4/sawmills-remote-operator-chart:2.0.23`. Its test archive SHA256 is `e054cf7bd788b161931f644693ea6d78da8694b6ef85c82d3f56785f410356ab`. Tests reuse the existing compatibility renderer and compare complete objects against that archive.

The default operator image is `0.343.0`. Recovery adds the `POD_UID` downward API field, the `sawmills.ai/health-gated-recovery: v1` Pod label, a 14,400-second termination grace and the existing local `/drain` preStop hook. Name helpers retain the original chart name. Proxy, analytics, autoscaler, managed-chart options, service accounts, RBAC, Secret references, resources, scheduling and cache behavior retain the 2.0.23 contract. An explicit image repository or tag override still takes precedence.

Chart versions come from the PR version label and release workflow. A checked-in baseline version is not a published release receipt. The new publishing workflow must land through the person-owned workflow route before publication; the existing 2.0.5 release workflow stays unchanged.

Run the preservation tests on the devbox:

```sh
python3 helm-charts/sawmills-remote-operator-compat/tests/test_compatibility.py
helm lint helm-charts/sawmills-remote-operator-2023-compat
helm unittest helm-charts/sawmills-remote-operator-2023-compat
```

For an operator-only upgrade, keep worker and LB Pod UIDs, Ready state, restart counts, workload specs, images and HPA/KEDA bindings unchanged. Evaluate each available loss metric with the same series set before and after. Record absent exporter-failure or queue metrics as UNKNOWN, including the resulting limit on loss detection. Any collector workload change requires rollback. These render tests establish chart preservation; they do not establish runtime acceptance, a private reference match or permission to upgrade a customer.
