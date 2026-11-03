# CES Helm charts

Helm charts for [Clyso Enterprise Storage](https://docs.clyso.com/docs/products/clyso-enterprise-storage/getting-started/)
(CES) on Kubernetes, through [Rook](https://rook.io). Each chart wraps an
upstream Rook or ceph-csi chart at an exact version, so one release of these
charts is one tested combination of them. The charts keep upstream's
defaults, apart from the CES image and the few that each chart's README
lists, so Rook's documentation applies to every setting.

| Chart | Installs | Wraps |
|---|---|---|
| [`ces-rook-operator`](charts/ces-rook-operator/) | the Rook operator and ceph-csi-operator, once per Kubernetes cluster | `rook-ceph` 1.21.1 |
| [`ces-csi-drivers`](charts/ces-csi-drivers/) | the Ceph CSI drivers, when pods use Ceph volumes | `ceph-csi-drivers` 1.1.0 |
| [`ces-ceph-cluster`](charts/ces-ceph-cluster/) | a CES cluster, one release per cluster | `rook-ceph-cluster` 1.21.1 |

## Installing

The charts are published to the Helm chart repository
`https://charts.ces.clyso.com`. Rook's pods run privileged: where Pod Security
admission is enforced, label the namespace
`pod-security.kubernetes.io/enforce=privileged` first. Then install the
three charts in this order, at the same version:

```console
helm repo add clyso https://charts.ces.clyso.com
helm repo update clyso
helm install ces-rook-operator clyso/ces-rook-operator --version 1.0.0 -n rook-ceph --create-namespace --wait
helm install ces-csi-drivers clyso/ces-csi-drivers --version 1.0.0 -n rook-ceph --wait
helm install ces-ceph-cluster clyso/ces-ceph-cluster --version 1.0.0 -n rook-ceph -f cluster.yaml
kubectl -n rook-ceph get cephcluster -w      # until HEALTH_OK
```

`cluster.yaml` names the CES release the cluster runs, such as
`rook-ceph-cluster.cephImage.tag: ces-v19.2.6-1`, which the chart requires,
and the cluster's own layout: its nodes and devices, pools and filesystems.

[`charts/README.md`](charts/README.md) covers the rest: installing from a git
checkout, upgrades, moving existing Rook releases onto these charts, running
without CSI, and how versions are numbered. Each chart's README lists its
settings and what it changes from upstream.

## Repository layout

| Path | Holds |
|---|---|
| [`charts/`](charts/) | the three charts, with their test cases in `charts/<chart>/tests/` |
| [`hack/`](hack/) | the scripts that fetch the pinned upstream charts, check the charts and package them, and the chart repository's landing page |
| [`.github/workflows/charts.yaml`](.github/workflows/charts.yaml) | checks every pull request, and publishes new chart versions from `main` |

## Working on the charts

```console
hack/check-charts.sh
```

It fetches the pinned upstream charts and checks them against their recorded
digests, checks that the three charts agree on their versions, then renders
and lints every test case. It needs Helm 3.13 or later and python3 with
PyYAML, and runs offline once the upstream charts are fetched.

To release, raise the version of all three charts and merge to `main`: the
workflow publishes each new version as a GitHub release, and adds it to the
chart repository's index ([Releasing](charts/README.md#releasing)).

## License

[Apache License 2.0](LICENSE).
