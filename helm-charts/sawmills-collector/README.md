# Sawmills Collector Helm Chart

A comprehensive Helm chart for deploying the Sawmills OpenTelemetry Collector with advanced observability features, autoscaling, and load balancing capabilities.

## Overview

The Sawmills Collector is a production-ready OpenTelemetry Collector distribution that collects, processes, and exports telemetry data (metrics, logs, and traces) to the Sawmills platform. This chart provides a complete deployment solution with enterprise-grade features.

> **Note**: In typical deployments, the Sawmills Collector is managed by the [Sawmills Remote Operator](../sawmills-remote-operator/README.md), which maintains a bidirectional gRPC session with the Sawmills controller and handles collector lifecycle management. This chart can also be deployed standalone for advanced use cases or custom configurations.

## Features

* **Multiple Deployment Modes**: Supports both Deployment and DaemonSet modes
* **Autoscaling**: Built-in support for Kubernetes HPA and KEDA-based autoscaling
* **Load Balancing**: Optional HAProxy integration for advanced load balancing
* **High Availability**: Configurable pod anti-affinity and topology spread constraints
* **Telemetry Collection**: Dedicated telemetry collector for internal metrics
* **Proxy Support**: HTTP/HTTPS proxy configuration for outbound traffic
* **Flexible Configuration**: S3-based or direct YAML configuration
* **Service Mesh Ready**: Compatible with service mesh architectures
* **Monitoring**: Prometheus metrics and ServiceMonitor support

## Prerequisites

* Kubernetes cluster (v1.19+)
* Helm 3.x
* Access to Sawmills container registry (`public.ecr.aws/s7a5m1b4`)
* (Optional) KEDA installed if using KEDA autoscaling
* (Optional) Prometheus Operator if using ServiceMonitor

## Installation

### Basic Installation

```bash
helm install my-collector ./helm-charts/sawmills-collector \
  --namespace sawmills-system \
  --create-namespace \
  --set prometheusremotewrite.endpoint="https://ingress.sawmills.ai" \
  --set-string appVersion="latest"
```

### With API Key Secret

```bash
helm install my-collector ./helm-charts/sawmills-collector \
  --namespace sawmills-system \
  --create-namespace \
  --set prometheusremotewrite.endpoint="https://ingress.sawmills.ai" \
  --set apiSecret.name="sawmills-secret" \
  --set apiSecret.key="api-key"
```

## Configuration

### Deployment Mode

The chart supports two deployment modes:

#### Deployment Mode (Default)

Standard Kubernetes Deployment with configurable replicas:

```yaml
mode: deployment
replicaCount: 3
```

#### DaemonSet Mode

Runs a collector pod on every node (or nodes matching nodeSelector):

```yaml
mode: daemonSet
# replicaCount is ignored in DaemonSet mode
```

### Basic Configuration

```yaml
# Collector identification
collectorName: sawmills-collector
collectorId: sawmills-collector-id

# Prometheus Remote Write endpoint
prometheusremotewrite:
  endpoint: https://ingress.sawmills.ai
  external_labels:
    pod_name: ${env:MY_POD_NAME}
    collector_name: ${env:COLLECTOR_NAME}
    collector_id: ${env:COLLECTOR_ID}

# Collector Gateway endpoint
collector_gateway:
  endpoint: https://ingress.sawmills.ai

# Quota Management Processor
quotamgmtprocessor:
  s3_bucket: sawmills-plat-ue1-prod-quotas
  folder_name: SAWMILLS_ORG
```

### Proxy Configuration

Customers that require all internet-bound traffic to pass through an HTTP/HTTPS proxy can set the `proxy` block. The chart wires these values into the `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` environment variables consumed by the collector so TLS sessions still terminate at Sawmills services.

```yaml
proxy:
  http: http://user:pass@corp-proxy.example.com:32281
  https: http://user:pass@corp-proxy.example.com:32281
  noProxy:
    - 10.0.0.0/8
```

If either `proxy.http` or `proxy.https` is set, the chart will automatically populate NO\_PROXY with the following predefined values:

* `localhost`, `127.0.0.1`, `::1`, `kubernetes`, `kubernetes.default.svc`, `.svc`, `.svc.cluster.local`, `.cluster.local`
* `$(KUBERNETES_SERVICE_HOST)` and `$(MY_POD_IP)`

Use `noProxy` to extend that list with any additional domains or CIDRs that must bypass your proxy.

You can also set them via the CLI:

```bash
helm upgrade --install my-collector ./helm-charts/sawmills-collector \
  --set proxy.https="http://$USER:$HOSTNAME@bar.proxy.square:32281" \
  --set proxy.http="http://$USER:$HOSTNAME@bar.proxy.square:32281" \
  --set proxy.noProxy[0]="kubernetes.default.svc" \
  --set proxy.noProxy[1]="10.0.0.0/8"
```

When the values are empty (default), the collector connects directly without a proxy. Internal cluster calls (for example, Kubernetes API access) continue to bypass the proxy regardless of these settings.

### Resource Configuration

```yaml
resources:
  requests:
    memory: 512Mi
    cpu: 250m
  limits:
    memory: 2.5Gi
    cpu: 3000m
  disableLimits: false  # Set to true to disable resource limits
```

### Autoscaling

#### Standard HPA

```yaml
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 50
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 120
      policies:
        - type: Percent
          value: 50
          periodSeconds: 120
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 25
          periodSeconds: 120
```

#### KEDA Autoscaling

```yaml
keda:
  enabled: true
  minReplicas: 2
  maxReplicas: 100
  pollingInterval: 30
  cooldownPeriod: 0
  scaling:
    cpu:
      enabled: true
      targetUtilization: 80
    memory:
      enabled: true
      targetUtilization: 80
    prometheus:
      enabled: false
      metricType: Value
      metadata:
        serverAddress: http://prometheus:9090
        query: sum(rate(http_requests_total[2m]))
        threshold: "100.50"
```

### HAProxy Load Balancing

Enable HAProxy for advanced load balancing:

```yaml
haproxy:
  enabled: true
  image: public.ecr.aws/docker/library/haproxy:3.1
  max_connections: 60000
  error_limit: 3
  probes:
    liveness:
      type: http # http|tcp
      port: 13135
      path: /healthcheck
    readiness:
      type: http # http|tcp
      port: 13135
      path: /healthcheck
  resources:
    requests:
      memory: 128Mi
      cpu: 50m
    limits:
      memory: 256Mi
      cpu: 100m
  prometheus:
    enabled: true
    port: 8405
  stats:
    enabled: true
    port: 8406
    uri: "/"
    refresh: "10s"
    auth: "admin:admin"
```

#### Per-Port TLS Termination

Enable TLS termination for specific HAProxy port mappings. When TLS is enabled on any port, the service switches to LoadBalancer type with AWS internal annotations.

> **Note:** TLS termination uses HAProxy's `crt-store` directive, which requires **HAProxy 3.0 or newer**. The chart defaults to HAProxy 3.1, but if you override `haproxy.image` to an earlier version, TLS configuration will fail to parse.

**Prerequisites:**

1. Create a Kubernetes TLS secret:
   ```bash
   kubectl create secret tls collector-tls \
     --cert=tls.crt \
     --key=tls.key \
     -n <namespace>
   ```

2. Configure TLS per port mapping:
   ```yaml
   haproxy:
     enabled: true
     tls:
       secretName: "collector-tls"
       certPath: "/etc/haproxy/certs"
     mapping:
       http_4318:
         from: 10000
         to:
           port: 4318
           protocol: TCP
         tls:
           enabled: true
           port: 443
   ```

This creates:

* HTTP frontend on port 10000 (plain traffic)
* HTTPS frontend on port 443 (TLS terminated, forwards to same backend)
* LoadBalancer service exposing port 443

### Ingress Configuration

#### NGINX Ingress

```yaml
ingress:
  type: nginx
  nginx:
    enabled: true
    className: nginx
    port: 4318
    annotations:
      kubernetes.io/ingress.class: nginx
      nginx.ingress.kubernetes.io/ssl-redirect: "false"
    hosts:
      - host: sawmills-collector.local
        paths:
          - path: /
            pathType: Prefix
```

#### HAProxy Ingress

```yaml
ingress:
  type: haproxy
  haproxy:
    enabled: true
    className: haproxy
    port: 4318
    annotations:
      kubernetes.io/ingress.class: haproxy
      haproxy.ingress.kubernetes.io/ssl-redirect: "false"
    hosts:
      - host: sawmills-collector.local
        paths:
          - path: /
            pathType: Prefix
```

### Node Selection and Affinity

```yaml
# Node selector
nodeSelector:
  kubernetes.io/os: linux

# Tolerations
tolerations:
  - key: "key1"
    operator: "Equal"
    value: "value1"
    effect: "NoSchedule"

# Pod anti-affinity (default spreads pods across nodes)
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - sawmills-collector-chart
          topologyKey: kubernetes.io/hostname

# Topology spread constraints
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: sawmills-collector-chart
```

### OpenTelemetry Collector Configuration

#### S3-Based Configuration (Recommended)

```yaml
otelConfig:
  s3path: "s3://my-bucket/collector-config.yaml"
  encryptionKey: "your-encryption-key"
```

#### Direct YAML Configuration

```yaml
otelCollectorConfig:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: ${env:MY_POD_IP}:4317
        http:
          endpoint: ${env:MY_POD_IP}:4318
  processors:
    memory_limiter:
      check_interval: 1s
      limit_mib: 820
      spike_limit_mib: 100
    batch:
      send_batch_max_size: 1000
      send_batch_size: 100
      timeout: 10s
  exporters:
    prometheusremotewrite:
      endpoint: ${env:PROMETHEUS_REMOTE_WRITE_ENDPOINT}
      headers:
        X-API-KEY: ${env:PROMETHEUS_REMOTE_WRITE_API_KEY}
  service:
    pipelines:
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [prometheusremotewrite]
```

### Additional Containers (Sidecars)

Add sidecar containers to the collector pod:

```yaml
additionalContainers:
  fluent-bit:
    image: fluent/fluent-bit:2.1
    imagePullPolicy: IfNotPresent
    command: ["/fluent-bit/bin/fluent-bit"]
    args: ["-c", "/fluent-bit/etc/fluent-bit.conf"]
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
    volumeMounts:
      - name: fluent-bit-config
        mountPath: /fluent-bit/etc/

additionalVolumes:
  - name: fluent-bit-config
    configMap:
      name: fluent-bit-config
```

See [examples/additional-containers.yaml](./examples/additional-containers.yaml) for a complete example.

### Service Configuration

```yaml
service:
  type: ClusterIP
  headless:
    enabled: true  # Recommended for StatefulSet-like behavior
  internalTrafficPolicy: "Local"  # Route traffic to local endpoints
  annotations:
    service.kubernetes.io/topology-mode: "Auto"
```

### ServiceMonitor (Prometheus Operator)

```yaml
serviceMonitor:
  enabled: true
  labels:
    release: prometheus
  metricsEndpoints:
    - port: prometheus
      interval: 15s
```

### Rollout Strategy

```yaml
rollout:
  strategy: RollingUpdate
  rollingUpdate:
    maxUnavailable: null   # defaults to 1 for ≤ 10 replicas, scales proportionally beyond that
    maxSurge: null         # defaults to 2 for ≤ 10 replicas, scales proportionally beyond that
  minReadySeconds: 15
  terminationGracePeriodSeconds: 60
  main:
    probes:
      liveness:
        initialDelaySeconds: 5
        periodSeconds: 5
        failureThreshold: 5
      readiness:
        initialDelaySeconds: 0
        periodSeconds: 5
      startup:
        enabled: true
        periodSeconds: 5
        failureThreshold: 12
    preStopSleepSeconds: 15
```

### Pod Disruption Budget

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: null  # defaults to replicaCount-1 when ≤ 5, otherwise ceil(0.8 * replicaCount)
```

## Examples

### Minimal Configuration

```yaml
prometheusremotewrite:
  endpoint: https://ingress.sawmills.ai

collector_gateway:
  endpoint: https://ingress.sawmills.ai

quotamgmtprocessor:
  s3_bucket: my-bucket
  folder_name: MY_ORG
```

### Production Configuration

```yaml
mode: deployment
replicaCount: 5

resources:
  requests:
    memory: 1Gi
    cpu: 500m
  limits:
    memory: 4Gi
    cpu: 4000m

autoscaling:
  enabled: true
  minReplicas: 5
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
                - sawmills-collector-chart
        topologyKey: kubernetes.io/hostname

haproxy:
  enabled: true
  max_connections: 100000
```

### DaemonSet Configuration

```yaml
mode: daemonSet

nodeSelector:
  node-role.kubernetes.io/worker: ""

tolerations:
  - effect: NoSchedule
    operator: Exists
```

## Advanced Features

### Load Balancer Component

Enable a separate load balancer deployment:

```yaml
loadBalancer:
  enabled: true
  replicas: 3
  minReadySeconds: 15
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  resources:
    requests:
      memory: 128Mi
      cpu: 250m
    limits:
      memory: 512Mi
      cpu: 500m
  storage:
    enabled: true
    size: 1Gi
    className: "standard"
```

#### Load Balancer Queue Compression Modes

Configure these options in `loadBalancer.otelCollectorConfig.exporters.<loadbalancing-exporter>.sending_queue`:

* `payload_compression`: `none`, `snappy`, or `zstd`
* `compress_in_memory`: boolean (for in-memory queue payload compression)

In-memory queue compression (no persistent storage):

```yaml
loadBalancer:
  enabled: true
  otelCollectorConfig:
    exporters:
      loadbalancing:
        sending_queue:
          enabled: true
          queue_size: 2000
          payload_compression: zstd
          compress_in_memory: true
```

Persistent queue + compression (disk-backed queue):

```yaml
loadBalancer:
  enabled: true
  storage:
    enabled: true
    size: 1Gi
    className: standard
  otelCollectorConfig:
    extensions:
      file_storage/otc:
        directory: /data/storage/otc
    exporters:
      loadbalancing:
        sending_queue:
          enabled: true
          queue_size: 2000
          storage: file_storage/otc
          payload_compression: zstd
    service:
      extensions: [health_check, file_storage/otc]
```

Validation guardrails in this chart:

* `sending_queue.storage` requires `loadBalancer.storage.enabled: true`
* `compress_in_memory: true` requires `sending_queue.enabled: true`
* `compress_in_memory: true` requires `payload_compression: snappy|zstd`
#### Remote Operator Metrics Scrape Leader Election

Use `remoteOperatorMetricsScrape` to scrape the remote-operator metrics service from telemetry-collector.

When `remoteOperatorMetricsScrape.leaderElection.enabled: true`:

* the chart switches `prometheus/remote_operator` from static target mode to local `http_sd` mode
* a `remote-operator-scrape-leader` sidecar is added (LB pods in LB mode, deployment pods otherwise)
* namespaced `Role`/`RoleBinding` resources are created to allow Lease operations in `leaderElection.leaseNamespace`

Configuration path: `remoteOperatorMetricsScrape.leaderElection`

* `enabled`: `true|false`
* `leaseName`, `leaseNamespace`
* `listenPort`, `sdRefreshInterval`
* `leaseDuration`, `renewDeadline`, `retryPeriod`
* `sidecar.image.*`, `sidecar.resources.*`

Minimal example:

```yaml
remoteOperatorMetricsScrape:
  enabled: true
  serviceName: sawmills-remote-operator-sawmills-remote-operator-chart
  namespace: sawmills-o11y
  port: 8086
  leaderElection:
    enabled: true
    leaseName: sawmills-collector-remote-operator-scrape-leader
    leaseNamespace: sawmills-o11y
```

Guardrails and dependencies:

* `leaderElection.enabled` is only effective when `remoteOperatorMetricsScrape.enabled: true`
* enabling leader election deploys an additional sidecar and Lease RBAC resources
* use a dedicated service account for least-privilege deployments
### KEDA Scaler

Enable the KEDA scaler component:

```yaml
kedaScaler:
  enabled: true
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 500m
      memory: 128Mi
```

## Troubleshooting

### Common Issues

#### Pods Not Starting

* Check resource limits and requests
* Verify image pull secrets if using private registry
* Review pod events: `kubectl describe pod <pod-name>`
* Check logs: `kubectl logs <pod-name>`

#### Configuration Errors

* Validate YAML syntax: `helm template . --debug`
* Check for missing required values
* Verify S3 access if using S3-based configuration
* Review collector logs for configuration parsing errors

#### Autoscaling Not Working

* Verify HPA/KEDA resources exist: `kubectl get hpa`
* Check metrics availability: `kubectl top pods`
* Review autoscaling events: `kubectl describe hpa <name>`

#### Proxy Issues

* Verify proxy URL format: `http://[user:pass@]host:port`
* Check NO\_PROXY settings for internal services
* Review collector logs for connection errors

### Debugging Commands

```bash
# Check pod status
kubectl get pods -n sawmills-system

# View collector logs
kubectl logs -f deployment/my-collector-sawmills-collector -n sawmills-system

# Check configuration
kubectl get configmap my-collector-sawmills-collector-config -n sawmills-system -o yaml

# Validate Helm template
helm template my-collector ./helm-charts/sawmills-collector --debug

# Dry-run installation
helm install my-collector ./helm-charts/sawmills-collector --dry-run --debug
```

## Upgrading

### Upgrade Chart

```bash
helm upgrade my-collector ./helm-charts/sawmills-collector \
  --namespace sawmills-system \
  --reuse-values
```

### Upgrade with New Values

```bash
helm upgrade my-collector ./helm-charts/sawmills-collector \
  --namespace sawmills-system \
  --set prometheusremotewrite.endpoint="https://new-endpoint.sawmills.ai"
```

## Uninstallation

```bash
helm uninstall my-collector --namespace sawmills-system
```

## Additional Resources

* [Main README](../../README.md) - Repository overview and contribution guidelines
* [Configuration Examples](./examples/) - Example configurations
* [Helm Documentation](https://helm.sh/docs/)
* [OpenTelemetry Collector Documentation](https://opentelemetry.io/docs/collector/)
* [Sawmills Platform Documentation](https://docs.sawmills.ai)

## Support

For issues, questions, or contributions, please:

* Create an issue in this repository
* Tag `@sawmills/engineers` in discussions
* Contact Sawmills support for urgent issues
