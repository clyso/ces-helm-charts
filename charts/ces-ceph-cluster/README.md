# ces-ceph-cluster

A Clyso Enterprise Storage (CES) cluster, run by the Rook operator from
`ces-rook-operator`. It wraps the upstream `rook-ceph-cluster` chart at
exactly **1.21.1** and runs the CES image
`harbor.clyso.com/ces/ceph/ceph`, at the CES release its values name.

Install it after `ces-rook-operator`, and after `ces-csi-drivers` if pods in
this Kubernetes cluster are to use its pools, from the chart repository
`https://charts.ces.clyso.com`:

```console
helm repo add clyso https://charts.ces.clyso.com
helm install ces-ceph-cluster clyso/ces-ceph-cluster --version 1.0.0 --namespace rook-ceph -f cluster.yaml
kubectl -n rook-ceph get cephcluster -w
```

From a git checkout, run `hack/fetch-subcharts.sh ces-ceph-cluster` first,
and install `charts/ces-ceph-cluster` instead; packaged releases already
contain the subchart.

## The CES release

The chart has no default CES release, and refuses to render until the values
name one:

```yaml
rook-ceph-cluster:
  cephImage:
    tag: ces-v19.2.6-1
```

A chart upgrade therefore never changes the Ceph release a cluster runs.
The tag must name a CES release, `ces-<version>`. Rook 1.21 runs CES releases
based on Ceph Squid from 19.2.0 and Tentacle from 20.2.1. Rook reads the
version from the image itself, and the toolbox runs the same image. Set the
image here only: `cephClusterSpec.cephVersion` is refused, since the upstream
template writes it from `cephImage`.

A values file that leaves `rook-ceph-cluster:` empty, for instance with every
key under it commented out, sets it to null. Helm then drops every setting
under it, this chart's and those of earlier values files alike, and the
chart refuses upstream's tag that fills in.

## What differs from upstream

Values behave as Rook documents them for `rook-ceph-cluster` 1.21.1, nested
under `rook-ceph-cluster:`. Anything else at the top level, except `global`,
is rejected. Only these defaults differ:

| Setting | Upstream | Here |
|---|---|---|
| `cephImage` | `quay.io/ceph/ceph:v20.2.4` | `harbor.clyso.com/ces/ceph/ceph`, no default tag |
| `toolbox.enabled` | `false` | `true` |
| Kubernetes versions | any | 1.32 to 1.37 |

## Upstream defaults to review

Everything else is upstream's. Among it:

- **Devices.** `cephClusterSpec.storage.useAllNodes` and `useAllDevices` are
  `true`: Rook takes every empty disk on every node. To list nodes and
  devices instead, set both to `false`; Rook ignores a `nodes` list
  otherwise.
- **Pools and StorageClasses.** `cephBlockPools` holds `ceph-blockpool`, with
  the StorageClass `ceph-block` as the cluster's default class.
  `cephFileSystems` holds `ceph-filesystem`, with a StorageClass of that
  name. `cephObjectStores` holds `ceph-objectstore`, with RGW on port 80 and
  the StorageClass `ceph-bucket`. The block and filesystem StorageClasses need
  `ces-csi-drivers`; `ceph-bucket` uses Rook's own bucket provisioner.
- **Failure domain.** `host`: each of upstream's pools spreads 3 copies or
  erasure-code chunks over 3 hosts, so it needs OSDs on at least 3 hosts.
- **Data directory.** `cephClusterSpec.dataDirHostPath` is `/var/lib/rook`.
  It cannot change later.

Helm merges maps but replaces lists. A pool, filesystem or object store list
in the values replaces upstream's whole list, and `[]` leaves none.

## More than one CES cluster

One operator can run several CephClusters, each with its own release and
namespace, fsid, mons, keys and disks. The chart checks nothing between them.
Keep these apart:

- **Data directories.** One per cluster, never one inside another's.
- **Devices.** Each cluster lists its own, with `useAllNodes` and
  `useAllDevices` off.
- **StorageClass and VolumeSnapshotClass names.** They are cluster-wide, and
  Helm refuses a release whose class another release already owns.
- **Host ports**, with host networking (`network.provider: host`). A mon
  claims ports 3300 and, unless msgr2 is required, 6789 on its node; a mgr
  claims 6800, 9283 and the dashboard's port. So the mons and mgrs of two
  clusters cannot share a node, and `monitoring.exporter.port` (default 9926)
  must differ between clusters whose daemons share one.

Raise `rook-ceph.reconcileConcurrentClusters` in `ces-rook-operator`, so that
one cluster's long reconcile does not hold up the others.

## Upgrades

Each cluster moves to a new CES release when its `cephImage.tag` changes:
Rook refuses while the cluster is in `HEALTH_ERR`, then replaces the daemons
one at a time. Rook itself is shared: upgrading `ces-rook-operator` reaches
every cluster. Do not `helm rollback` past a revision that changed the tag:
Rook rolls the older image out, logging only that downgrades are not
supported.

To move an existing upstream `rook-ceph-cluster` release to this chart,
upgrade it in place and keep its release name, with its values nested under
`rook-ceph-cluster:` and the image it runs today, as `helm get values --all`
shows it, under `cephImage`. Rook 1.21 added CSI secret parameters to the
default block StorageClass, and StorageClass parameters cannot change in
place: delete that StorageClass before the upgrade. Existing volumes are not
affected.
