# ces-rook-operator

The Rook operator for Clyso Enterprise Storage (CES). It wraps the upstream
`rook-ceph` chart at exactly **1.21.1**, which bundles ceph-csi-operator
**1.1.0**, so one version of this chart always installs the same operator,
CRDs and RBAC.

Install it once per Kubernetes cluster, before `ces-csi-drivers` and the
`ces-ceph-cluster` releases:

```console
helm install ces-rook-operator charts/ces-rook-operator --namespace rook-ceph --create-namespace
```

Rook's pods run privileged: where Pod Security admission is enforced, label
the namespace `pod-security.kubernetes.io/enforce=privileged` first.

From a git checkout, run `hack/fetch-subcharts.sh ces-rook-operator` first.
It fetches the pinned subchart and checks it against `dependencies.sha256`.
`helm dependency build` would need the upstream repository added with `helm
repo add`, and does not check the archive. Packaged releases already contain
the subchart.

## What differs from upstream

| Setting | Upstream | Here | Why |
|---|---|---|---|
| Kubernetes versions | any | 1.32 to 1.37 (`kubeVersion`) | Rook 1.21's tested range; Helm refuses anything else |
| `csi.createCsiOperatorResources` | empty, which Rook reads as `true` when it starts | `true` | a running operator that sees it change from `true` to empty deletes every cluster's CephConnection and ClientProfile |
| Keys outside `rook-ceph:` | ignored | rejected | a setting at the wrong level fails instead of vanishing |

Every other default is upstream's, with Rook's documentation for the
`rook-ceph` chart.

## Values

Upstream settings go under `rook-ceph:`. Anything else at the top level,
except `global`, is rejected. Inside `rook-ceph:` the chart checks nothing:

```yaml
rook-ceph:
  reconcileConcurrentClusters: 4   # with several CephClusters: reconcile 4 at once
  resources:
    limits:
      memory: 1Gi
```

Since Rook 1.20 the operator chart no longer configures the CSI drivers.
Settings such as `csi.provisionerReplicas` or `csi.kubeletDirPath` belong in
`ces-csi-drivers`; here the upstream chart ignores them. What remains under
`csi:` are the switches below, `csi.serviceMonitor`, and the CSI images:
`rook-ceph.csi.cephcsi`, `.registrar`, `.provisioner`, `.snapshotter`,
`.attacher`, `.resizer` and `.csiAddons` each take a `repository` and `tag`,
and an image is used only when both are set. Left empty, ceph-csi-operator
v1.1.0 uses its built-in images. Set them when mirroring images for an
air-gapped site.

## Without CSI

CSI is needed only for Ceph volumes in this Kubernetes cluster:
StorageClasses, and the pods that mount them. Clients outside Kubernetes
reach Ceph without it. To run without CSI, do not install `ces-csi-drivers`:
no CSI plugin runs then.

Keep the CSI operator installed all the same. For clusters without CSI, Rook
documents leaving it out with `csi.installCsiOperator: false`, together with
`csi.createCsiOperatorResources: false`. But Rook 1.21.1 still watches
ClientProfile objects in two of its controllers, so without that CRD its
operator exits about two minutes after each start
([rook/rook#18654](https://github.com/rook/rook/issues/18654)). The chart
passes both settings through for when that is fixed. Until then, an unused
CSI operator can be scaled to zero:

```yaml
rook-ceph:
  ceph-csi-operator:
    controllerManager:
      replicas: 0
```

Turning `installCsiOperator` off on an installed release also deletes the
CSI CRDs, as described below.

## Upgrade, never uninstall

Rook's 21 CRDs carry `helm.sh/resource-policy: keep`; the six CRDs of the
bundled ceph-csi-operator do not, and the subchart offers no switch for it.
Uninstalling this release therefore deletes those CRDs, every `Driver` object
with them, and the CSI plugins of **every** CephCluster. Turning
`csi.installCsiOperator` off on an installed release does the same: Helm
removes the subchart and its CRDs.

## Moving an existing upstream release to this chart

Upgrade the existing release in place and keep its name, with its old values
nested under `rook-ceph:`:

```console
helm upgrade rook-ceph charts/ces-rook-operator --namespace rook-ceph -f values.yaml
```

Helm lets a release change charts, and the subchart renders the same objects
as before. Do not uninstall the upstream release to install this one; that
deletes the CSI CRDs as described above. Do not rename the release either:
the ceph-csi-operator Deployment's selector contains the release name, and a
selector cannot change in place. Rook upgrades one minor at a time, so the
release must already run Rook 1.20.
