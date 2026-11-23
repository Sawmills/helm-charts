# Sawmills Helm Charts

These charts define how Sawmills Collectors and Remote Operators run in Kubernetes. The terms cover release configuration, telemetry flow, and ownership of collector changes.

## Language

### Charts and Releases

**Collector Chart**:
The Helm package that defines the Sawmills Collector workloads and their supporting Kubernetes resources.

**Helm Release**:
A named installation of a chart in a Kubernetes namespace. Each install, upgrade, or rollback creates a Helm revision.
_Avoid_: chart, pod

**Helm Release Values**:
The desired settings for a Helm Release in a particular environment, applied when Helm renders the chart's Kubernetes resources.
_Avoid_: chart source, rendered manifests

**Chart Version**:
The version of the Helm package used for a release.
_Avoid_: image version, release revision

**Image Version**:
The version of the Collector or Remote Operator software selected to run in a pod. An image digest identifies the exact image.

### Collector Workloads

**Collector**:
A configured telemetry sender with its own collector identity inside a tenant. Its workloads can include both Workers and Load Balancers.
_Avoid_: pod, collector process

**Worker**:
A Collector workload role that processes telemetry and exports it to destinations. In a two-tier Collector, Workers receive traffic from Load Balancers.
_Avoid_: Load Balancer, telemetry sidecar

**Load Balancer (LB)**:
The optional Collector workload role that accepts telemetry and distributes it to Workers.
_Avoid_: Kubernetes LoadBalancer Service, HAProxy alone

**Telemetry Sidecar**:
A separate process in a Worker or Load Balancer pod that receives and exports internal telemetry.

**Collector Workload Mode**:
The choice between a Deployment with a replica count and a DaemonSet that runs a Worker on each eligible node.
_Avoid_: management mode, two-tier topology

**Collector Configuration**:
The runtime definition of the Collector's pipelines and settings. The chart can supply it inline or refer to a configuration artifact.
_Avoid_: Helm Release Values as a whole

**Pipeline**:
The configured path through receivers, processors, and exporters for a telemetry signal.

### Traffic and Capacity

**Central Queue**:
A buffer on a Load Balancer that holds accepted telemetry pending delivery.
_Avoid_: shared queue across all Load Balancers

**Stable Headless Service**:
The Load Balancer traffic Service whose DNS name is a contract with other workloads across chart upgrades.
_Avoid_: peer membership Service

**LB Membership Discovery**:
The process of finding peer Load Balancers for queue redistribution. The chart supports discovery through Kubernetes EndpointSlices or a separate DNS membership Service.

**Sibling Fallback**:
Backup routing that gives another Load Balancer a chance to accept a request when the local Collector is unavailable.
_Avoid_: external fallback, active sibling balancing

**Pressure Readiness**:
An optional Load Balancer readiness check that accounts for queue pressure, resource use, and recent delivery to Workers.
_Avoid_: liveness, proof of drain completion

**Backend Drain**:
The bounded shutdown phase in which a Collector backend becomes unready and has time to finish accepted work.
_Avoid_: immediate stop

**Collector Autoscaling**:
Automatic adjustment of Worker or Load Balancer replica counts according to configured scaling targets.

### Operator and Management

**Remote Operator**:
The component in the cluster that connects to Sawmills to manage or observe Collector installations.

**Managed Release**:
A Collector Helm Release whose install, upgrade, and removal are managed through the Remote Operator.
_Avoid_: manual deployment

**Manual Deployment**:
A Collector installation whose Helm changes a cluster user applies directly. The Remote Operator can still support runtime tasks such as processor hot reload and Live Tail.
_Avoid_: managed release

**Compatibility Chart**:
A Remote Operator chart for upgrades from a specific older chart version. It preserves the existing release's resource names and values behavior.
