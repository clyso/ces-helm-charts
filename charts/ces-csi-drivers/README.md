# ces-csi-drivers

The Ceph CSI drivers for Clyso Enterprise Storage (CES) on Rook. It wraps the
upstream `ceph-csi-drivers` chart at exactly **1.1.0**, the release that
matches the ceph-csi-operator bundled in `ces-rook-operator`.

Since Rook 1.20, CSI is split in two: `ces-rook-operator` installs
ceph-csi-operator and its CRDs, and this chart creates the `Driver` and
`OperatorConfig` objects that make the operator deploy the CSI plugins. One
set of drivers serves every CephCluster the Rook operator manages. Each
StorageClass selects its cluster through `clusterID`.

CSI is needed only for Ceph volumes in this Kubernetes cluster:
StorageClasses, and the pods that mount them. Clients outside Kubernetes
reach Ceph without it. Without CSI, skip this chart: no CSI plugin runs
then. `ces-rook-operator` keeps the CSI operator all the same, because Rook
1.21.1 needs its CRDs; that chart's README says why.

Install it once, after `ces-rook-operator` and in the same namespace:

```console
helm install ces-csi-drivers charts/ces-csi-drivers --namespace rook-ceph
```

From a git checkout, run `hack/fetch-subcharts.sh ces-csi-drivers` first;
packaged releases already contain the subchart.

## What differs from upstream

The upstream defaults do not work with Rook. The chart's defaults are Rook
1.21.1's recommended values for it, and it adds these checks:

| Setting | Upstream | Here | Why |
|---|---|---|---|
| Release namespace | any | must equal `operatorConfig.namespace` | Rook uses only drivers in its own namespace |
| Driver names | as given | must be `<operator namespace>.<driver>.csi.ceph.com` | the provisioner Rook writes into its StorageClasses |
| Keys outside `ceph-csi-drivers:` | ignored | rejected | a setting at the wrong level fails instead of vanishing |

Upstream turns on VolumeSnapshots for CephFS (`snapshotPolicy:
volumeSnapshot`) and leaves them off for RBD (`none`). A driver with a
snapshot policy needs the `snapshot.storage.k8s.io` CRDs and the snapshot
controller in the Kubernetes cluster; where they are missing, set
`snapshotPolicy: none` on it.

## Values

Upstream settings go under `ceph-csi-drivers:`; anything else at the top
level, except `global`, is rejected. Inside, the chart checks nothing beyond
the release namespace and the driver names. Settings that Rook 1.19 took
under `csi:` in the operator chart live here now: per driver in
`drivers.<name>`, or for all drivers in `operatorConfig.driverSpecDefaults`.

Prefer setting them per driver. The upstream chart writes most fields into
every Driver from the driver's own values, and a Driver's own value takes
precedence, so a default reaches the drivers only for fields they leave
unset, such as `nodePlugin.kubeletDirPath`, `enableSeLinuxHostMount` and the
priority classes. Rook's documentation shows `controllerPlugin.replicas` and
`deployCsiAddons` as defaults; with ceph-csi-drivers 1.1.0 they have no effect
there.

```yaml
ceph-csi-drivers:
  operatorConfig:
    driverSpecDefaults:
      nodePlugin:
        kubeletDirPath: /srv/kubelet    # a kubelet outside /var/lib/kubelet
        enableSeLinuxHostMount: true    # hosts that enforce SELinux
  drivers:
    rbd:
      deployCsiAddons: true
      snapshotPolicy: volumeSnapshot
      controllerPlugin:
        replicas: 2       # Rook 1.19 ran two; ceph-csi-drivers defaults to one
        resources:
          provisioner:
            limits:
              memory: 512Mi
    cephfs:
      controllerPlugin:
        replicas: 2
```

Resources are set per container: `nodePlugin.resources` takes `registrar`,
`liveness`, `addons`, `logRotator` and `plugin`; `controllerPlugin.resources`
takes `attacher`, `snapshotter`, `resizer`, `provisioner`, `omapGenerator`,
`liveness`, `addons`, `logRotator` and `plugin`.

Rook 1.21 no longer pins CSI images; ceph-csi-operator v1.1.0 uses its
built-in ones. To pin or mirror them, set `rook-ceph.csi.*` in
`ces-rook-operator`, which writes the image set this chart points the
drivers at.

## Upgrades

Upgrade this release together with `ces-rook-operator`, never on its own:
the two pins move together. Uninstalling this release removes the CSI
plugins of every CephCluster.
