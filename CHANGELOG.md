# Changelog

## Unreleased

### Added

* The collector chart has a default-off LB shutdown budget check and automatic grace calculation (FLT-702).
  It adds sequential queue drain, preStop, telemetry and cleanup allowances while preserving existing off-mode renders.
* The collector chart can keep LB telemetry alive until main stops with `loadBalancer.telemetryNativeSidecar` (FLT-701).
  This value defaults to `false` and requires Kubernetes 1.33 or newer.
* With `rbac.storageClassDiscovery.enabled=true`, the remote-operator chart grants `get` and `list` on `storage.k8s.io/storageclasses` through a separate ClusterRole and binding (SAW-13246).
  A cluster permission owner must install the grant before operators can discover storage classes.
