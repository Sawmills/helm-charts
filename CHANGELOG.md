# Changelog

## Unreleased

### Added

* The collector chart can keep LB telemetry alive until main stops with `loadBalancer.telemetryNativeSidecar` (FLT-701).
  This value defaults to `false` and requires Kubernetes 1.33 or newer.
* With `rbac.storageClassDiscovery.enabled=true`, the remote-operator chart grants `get` and `list` on `storage.k8s.io/storageclasses` through a separate ClusterRole and binding (SAW-13246).
  A cluster permission owner must install the grant before operators can discover storage classes.
