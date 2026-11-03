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

The released charts are in the Helm chart repository
`https://charts.ces.clyso.com`, which the workflow in
`.github/workflows/charts.yaml` publishes from main (see "Releasing"). Add it
under a name of your choice:

```console
helm repo add clyso https://charts.ces.clyso.com
helm repo update clyso
```

Rook's pods run privileged: where Pod Security admission is enforced, label
each namespace `pod-security.kubernetes.io/enforce=privileged` first. Then
install in this order, each at the same exact version, waiting for each step:

```console
helm install ces-rook-operator clyso/ces-rook-operator --version 1.0.0 -n rook-ceph --create-namespace --wait
helm install ces-csi-drivers clyso/ces-csi-drivers --version 1.0.0 -n rook-ceph --wait
helm install ces-ceph-cluster clyso/ces-ceph-cluster --version 1.0.0 -n rook-ceph -f cluster.yaml
kubectl -n rook-ceph get cephcluster -w      # until HEALTH_OK
```

Without `helm repo add`, `--repo https://charts.ces.clyso.com` and
the bare chart name do the same. The packages carry the upstream charts, so
nothing is fetched from upstream.

### From a git checkout

A branch or commit that has no release yet installs from a checkout. Helm
cannot install from a git repository itself: `--repo` needs an `index.yaml`
at the URL it is given. Clone the ref, fetch the upstream charts it pins, and
use the chart directories in place of `clyso/<chart>`:

```console
git clone --depth 1 --branch <ref> https://github.com/clyso/ces-helm-charts
cd ces-helm-charts
hack/fetch-subcharts.sh
helm install ces-rook-operator charts/ces-rook-operator -n rook-ceph --create-namespace --wait
```

`hack/fetch-subcharts.sh` downloads the pinned upstream charts, which git
doesn't hold, from charts.rook.io and ceph.github.io, and checks each archive
against `dependencies.sha256`. With a local path, the checkout decides the
chart version, and Helm ignores `--version`. Each release is tagged
`<chart>-<version>`, such as `ces-rook-operator-1.0.0`: cloning that tag
gets the three charts as released.

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
`HEALTH_OK`:

```console
helm repo update clyso
helm upgrade ces-rook-operator clyso/ces-rook-operator --version <new> -n rook-ceph --wait
helm upgrade ces-csi-drivers clyso/ces-csi-drivers --version <new> -n rook-ceph --wait
helm upgrade ces-ceph-cluster clyso/ces-ceph-cluster --version <new> -n rook-ceph -f cluster.yaml
```

From a checkout of the new version, the chart directories take the place of
`clyso/<chart> --version <new>`.

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
values nested under the upstream chart's name:

```console
helm upgrade rook-ceph clyso/ces-rook-operator --version 1.0.0 -n rook-ceph -f operator.yaml
helm upgrade ceph-csi-drivers clyso/ces-csi-drivers --version 1.0.0 -n rook-ceph -f drivers.yaml
helm upgrade rook-ceph-cluster clyso/ces-ceph-cluster --version 1.0.0 -n rook-ceph -f cluster.yaml
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
| `hack/package-charts.sh <dir>` | packages each chart version that has no release yet, for the release workflow |

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

## Releasing

`.github/workflows/charts.yaml` runs `hack/check-charts.sh` on every pull
request that touches the charts. On main it also publishes each chart
version that has no release yet: a GitHub release named `<chart>-<version>`
carries the package, and `index.yaml` on the `gh-pages` branch, which GitHub
Pages serves, lists it. To release:

1. Raise `version` in all three `Chart.yaml` files, as "Versions" describes;
   `hack/check-versions.py` requires them equal.
2. Merge to main.

A released chart cannot change under its version: the workflow fails when a
chart differs from its release tag in anything but its tests and schema
source. Packaging is done by `hack/package-charts.sh` rather than by
chart-releaser, whose `helm dependency update` would replace the checked
subcharts.

The workflow also keeps a landing page, `index.html`, beside `index.yaml`. It
is made from `hack/pages/index.html` by `hack/render-pages.py`, and shows how
to add the repository, the charts at their newest versions, and how to
install CES. The page takes the repository's address from wherever it is
served, so a custom domain needs no change to it.

Once per repository, after the first release has created the `gh-pages`
branch:

1. In Settings, Pages, deploy from the branch `gh-pages`, folder `/ (root)`.
2. Point the domain at GitHub with a DNS `CNAME` record, `charts.ces.clyso.com`
   to `clyso.github.io`, and set it as the custom domain in the same
   settings. GitHub adds a `CNAME` file to `gh-pages`, which the workflow
   leaves in place. Enforce HTTPS once GitHub has issued the certificate.
3. Verify the domain in the organization's Pages settings, so that no other
   repository can serve it.

Signing is optional. With these set in the repository's Actions settings,
every package gets a `.prov` file, which `helm install --verify --keyring
<public keyring>` checks against the published public key:

- secret `HELM_SIGNING_KEYRING`: the signing key, as `gpg --export-secret-keys
  <key> | base64 -w0` prints it;
- secret `HELM_SIGNING_PASSPHRASE`: its passphrase;
- variable `HELM_SIGNING_KEY`: the key's name, such as its email address.
