# Changelog

## Unreleased

### Added

* The remote-operator chart grants `get` and `list` on `storage.k8s.io/storageclasses` through a separate ClusterRole and binding (SAW-13246).
  A cluster permission owner must install the grant before operators can discover storage classes.
