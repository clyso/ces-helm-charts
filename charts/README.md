# Clyso charts for CES on Rook

Three Helm charts that install Clyso Enterprise Storage (CES) through Rook.
Each wraps an upstream chart at an exact version, so one release of these
charts is one tested combination of Rook and ceph-csi:

| Chart | Wraps | Install |
|---|---|---|
| [`ces-rook-operator`](ces-rook-operator/) | `rook-ceph` 1.21.1, with ceph-csi-operator 1.1.0 | once, in `rook-ceph` |
| [`ces-csi-drivers`](ces-csi-drivers/) | `ceph-csi-drivers` 1.1.0 | once, in `rook-ceph`, only for Ceph volumes in Kubernetes |
| [`ces-ceph-cluster`](ces-ceph-cluster/) | `rook-ceph-cluster` 1.21.1, with the CES image | once per CES cluster |

The charts keep upstream's defaults, except for the CES image and the few
that each chart's README lists, and check little of what is passed on. Rook's
documentation applies to every setting, and a new Rook release mostly means
moving the pins.

There are three charts rather than one for two reasons. None of the upstream
charts uses a `crds/` directory: the CRDs are ordinary templates, and a Helm
release cannot create a CRD together with objects of that kind. The drivers
chart creates `Driver` objects and a cluster release creates a `CephCluster`,
and both CRDs come from the operator chart. And the operator exists once per
Kubernetes cluster and the drivers only where pods use Ceph volumes, while
each CES cluster is a release of its own, upgraded or removed on its own.

## Installing

No chart repository serves these charts yet, and Helm cannot install from a
git repository: `--repo` needs an `index.yaml` at the URL it is given. Until
the charts are published, install them from a checkout of this repository,
where `<ref>` is a branch, such as `main`, or a tag:

```console
git clone --depth 1 --branch <ref> https://github.com/clyso/ces-manifests
cd ces-manifests
hack/fetch-subcharts.sh
```

`hack/fetch-subcharts.sh` downloads the pinned upstream charts, which git
doesn't hold, from charts.rook.io and ceph.github.io, and checks each archive
against `dependencies.sha256`. A branch moves: to install the same charts
again later, clone a tag.

Rook's pods run privileged: where Pod Security admission is enforced, label
each namespace `pod-security.kubernetes.io/enforce=privileged` first. Then
install in this order, waiting for each step:

```console
helm install ces-rook-operator charts/ces-rook-operator -n rook-ceph --create-namespace --wait
helm install ces-csi-drivers charts/ces-csi-drivers -n rook-ceph --wait
helm install ces-ceph-cluster charts/ces-ceph-cluster -n rook-ceph -f cluster.yaml
kubectl -n rook-ceph get cephcluster -w      # until HEALTH_OK
```

With a local path, the checkout decides the chart version, and Helm ignores
`--version`. Once the charts are published, the same commands take them from
the repository by an exact version instead: `ces/ces-rook-operator --version
1.0.0` after `helm repo add ces <repository URL>`, or `ces-rook-operator
--repo <repository URL> --version 1.0.0`. The packages carry the upstream
charts, so nothing is fetched from upstream then.

`ces-csi-drivers` is needed only for Ceph volumes in this Kubernetes
cluster; without it, no CSI plugin runs. Keep the CSI operator of
`ces-rook-operator` all the same: Rook 1.21.1 needs its CRDs, as that chart's
README explains.

`cluster.yaml` names the CES release the cluster runs, which the chart
requires, and the cluster's own layout. The cluster chart's README lists the
upstream defaults that apply otherwise, such as taking every empty disk on
every node:

```yaml
rook-ceph-cluster:
  cephImage:
    tag: ces-v19.2.6-1
  cephClusterSpec:
    storage:
      useAllNodes: false
      useAllDevices: false
      nodes:
        - name: node-1
          devices:
            - name: /dev/disk/by-id/wwn-0x5000c500a1b2c301
```

Settings for an upstream chart go under its name: `rook-ceph:`,
`ceph-csi-drivers:` or `rook-ceph-cluster:`. Each chart rejects any other
top-level key, where Helm would ignore it. Helm merges maps but replaces
lists, so changing one pool means restating the list.

## Upgrading

The three charts are released together, under one version. Upgrade them in
order, operator first, and wait for every CES cluster to return to
`HEALTH_OK`. From a checkout of the new version, made as for installing:

```console
helm upgrade ces-rook-operator charts/ces-rook-operator -n rook-ceph --wait
helm upgrade ces-csi-drivers charts/ces-csi-drivers -n rook-ceph --wait
helm upgrade ces-ceph-cluster charts/ces-ceph-cluster -n rook-ceph -f cluster.yaml
```

From a chart repository, the charts and `--version <new>` take the place of
the paths.

A chart upgrade leaves each cluster on the CES release its values name.
Moving a cluster to another CES release is a change of
`rook-ceph-cluster.cephImage.tag` in its values, made on its own.

Never uninstall `ces-rook-operator` or `ces-csi-drivers` while a CephCluster
exists. The ceph-csi-operator CRDs carry no keep policy, so uninstalling the
operator deletes them along with the CSI drivers of every CES cluster, and
uninstalling the drivers removes the drivers.

Rook moves one minor version at a time. A cluster on Rook 1.19 goes to 1.20
with the upstream charts first, installing `ceph-csi-drivers` along the way,
and only then to these charts. The values files this repository shipped for
the upstream Rook 1.19 charts are kept at the tag `rook-1.19-values`.

## Moving existing upstream releases to these charts

Upgrade each upstream release in place, keeping its release name, with its
values nested under the upstream chart's name. From a checkout:

```console
helm upgrade rook-ceph charts/ces-rook-operator -n rook-ceph -f operator.yaml
helm upgrade ceph-csi-drivers charts/ces-csi-drivers -n rook-ceph -f drivers.yaml
helm upgrade rook-ceph-cluster charts/ces-ceph-cluster -n rook-ceph -f cluster.yaml
```

Helm lets a release change charts, and the subcharts render the same
objects as before. Do not uninstall the upstream releases instead, because
that deletes the CSI CRDs. Do not rename them either: the ceph-csi-operator
Deployment's selector contains the release name and cannot change in place.
`cluster.yaml` must name the image the cluster runs today under
`cephImage`; the cluster chart's README covers the rest. Rehearse the whole
sequence on a staging cluster.

## Versions

The charts share one SemVer version. The major number changes with the
pinned Rook minor, since Rook's upgrade-path rules then apply. The minor
number changes for a Rook patch, and the patch number for changes of our
own. Pre-release suffixes such as `1.21.1-ces.1` are not used: Helm hides
those versions unless `--devel` is given.

A new CES release needs no chart release: each cluster names its own, from
the Ceph releases the pinned Rook supports. Keep this table current; it is
not part of the chart packages, so it can change between chart releases:

| Charts | Rook | ceph-csi-operator | CES releases |
|---|---|---|---|
| 1.0.0 | 1.21.1 | 1.1.0 | based on Ceph Squid from 19.2.0, or Tentacle from 20.2.1 |

## Working on the charts

| Command | Does |
|---|---|
| `hack/fetch-subcharts.sh` | fetches the pinned subcharts and checks them against Chart.yaml, Chart.lock and `dependencies.sha256` |
| `hack/gen-schemas.py` | writes each `values.schema.json` from its `values.schema.yaml` |
| `hack/check-versions.py` | checks that the charts pin one consistent set of versions, and that each `appVersion` names its upstream pin |
| `hack/check-charts.sh` | runs all of the above, then renders and lints every case in `tests/`; offline once the subcharts are fetched |

The checks need Helm 3.13 or later, and python3 with PyYAML.

To move to a new Rook release:

1. Change the pins in all three `Chart.yaml` files, their `appVersion` and
   `clyso.com/*` annotations, and the chart versions.
2. Write each `Chart.lock` with `helm dependency update`, and check that it
   records exactly the pinned version. Rook's index lists each release
   twice, as `1.21.1` and `v1.21.1`, with different archives, and
   `hack/fetch-subcharts.sh` rejects a lock that names the other one.
3. Record the archives' sha256 in each `dependencies.sha256`, after checking
   them against the `digest` in the upstream repository index.
4. Read Rook's upgrade notes, and the upstream `values.yaml` changes for the
   defaults these charts override.
5. Add the new row to the table above, with the Ceph releases the new Rook
   supports.
6. Run `hack/check-charts.sh`.

To release a version, run `hack/check-charts.sh`, `helm package` each chart
(the subcharts go into the package), sign the packages, and push them to the
chart repository.
