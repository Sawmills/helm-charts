# Optional Egress NetworkPolicy

The collector, standard operator, and manual operator charts can each render a Kubernetes egress policy. It is disabled by default. Enable it only after defining the destinations that the selected workloads need.

The policy selects Pods in the release namespace by `app.kubernetes.io/instance`, including collector workers, load balancers, the KEDA scaler, and optional observer Pods. It sets `policyTypes: [Egress]`; it adds no ingress restriction. Compatibility recovery charts retain their historical manifests and do not include this option.

## Configure the Rules

Use the same values interface in each chart:

```yaml
networkPolicy:
  enabled: false
  egress: []
```

With `enabled: true`, an empty `egress` list denies all outbound traffic selected by this policy. The chart adds no automatic allowances. Rules use the native Kubernetes NetworkPolicy format and render without template evaluation. An empty rule `{}` permits all egress; a port-only rule permits that port to every destination. Use explicit destination peers for a restricted policy.

This example allows cluster DNS and one HTTPS destination. Replace the documentation address and DNS labels with approved values for your cluster. It is an illustration, not a complete Sawmills allowlist.

```yaml
networkPolicy:
  enabled: true
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - ipBlock:
            cidr: 203.0.113.10/32
      ports:
        - protocol: TCP
          port: 443
```

## Required Destinations

Review every enabled feature and configured receiver/exporter before enabling the policy:

* All selected Pods need their actual DNS resolver, usually UDP and TCP 53. NodeLocal DNS can require an explicit resolver IP instead of the example Pod selectors.
* Operators need `operatorAddress` (default `https://controller.sawmills.ai`) and `remoteWriteUrl` (default `https://ingress.sawmills.ai`), normally TCP 443. They also need the cluster's Kubernetes API address and port for their configured read and reconciliation operations.
* Standard operators that manage Helm releases need their configured chart registries and registry download endpoints, including `public.ecr.aws` and its backing download endpoints when using Sawmills OCI charts. Repository overrides can add destinations. The manual operator does not perform managed collector Helm operations.
* Collector telemetry uses its configured exporters, including `ingress.sawmills.ai` for default remote-write/OTLP settings. Other customer exporters, pull receivers, object storage, and authentication providers need their own destination rules.
* Collector load balancers need the configured worker and sibling destinations. Permit the relevant peer Pods and transport ports within the namespace. Traffic between Pods in the same release also needs explicit rules.
* When `kedaScaler.enabled=true`, workers and load balancers need the scaler Service OTLP receiver (`kedaScaler.service.otlpReceiverPort`, default TCP 4518). The scaler Pods are selected by the policy too. Allow their configured telemetry destinations and the metric-source traffic required by the selected scaler configuration.
* Membership discovery and the worker CPU observer need the Kubernetes API address and port. The observer also needs its configured remote-write destination. Other optional sidecars or features can add destinations.
* When an outbound proxy is configured, permit its address and port plus every direct destination covered by `NO_PROXY`, including internal cluster services where required.

Kubernetes NetworkPolicy has no DNS-name destination field. Resolve approved endpoints into maintained IP/CIDR rules, or manage DNS-aware rules through your CNI outside this chart. Do not replace dynamic service endpoints with stale example IPs. Image pulls run through the node runtime; allowing Pod egress does not configure node image-pull access.

## Cluster Limits and Rollback

The CNI must enforce NetworkPolicy. This chart does not verify enforcement. Service translation, API-server routing, NodeLocal DNS, host networking, IPv6, and cloud metadata endpoints depend on the cluster. Include the actual addresses and ports observed by your CNI.

Kubernetes combines policies additively. Another policy that permits broad egress can weaken the intended restriction. Review all policies selecting these Pods. This option does not restrict other releases or every Pod in the namespace.

Render the chart and check the resulting rules before an approved installation. Verify DNS, controller connectivity, telemetry delivery, configured exporters, and required cluster operations after enabling. To remove this chart's restriction, set `networkPolicy.enabled=false` in an approved Helm upgrade. Other policies still apply.
