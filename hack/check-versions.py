#!/usr/bin/env python3
"""Check that the Clyso charts pin one consistent set of upstream versions.

The charts are released together, so they must agree on their own version
and kubeVersion. Each upstream dependency must match the version annotation
that names it, and those annotations must agree across charts. The
ceph-csi-drivers pin must match the ceph-csi-operator that the vendored
rook-ceph archive bundles.

    hack/check-versions.py
"""

import pathlib
import sys
import tarfile

import yaml

CHARTS = pathlib.Path(__file__).resolve().parent.parent / "charts"

# Upstream dependency -> the annotation that records its version.
PINS = {
    "rook-ceph": "clyso.com/rook-version",
    "ceph-csi-drivers": "clyso.com/ceph-csi-operator-version",
}


def bundled_csi_operator(chart: pathlib.Path, rook_version: str) -> str | None:
    """The ceph-csi-operator version the vendored rook-ceph archive depends on."""
    archive = chart / "charts" / f"rook-ceph-{rook_version}.tgz"
    if not archive.exists():
        return None
    with tarfile.open(archive) as tar:
        meta = yaml.safe_load(tar.extractfile("rook-ceph/Chart.yaml"))
    for dep in meta.get("dependencies", []):
        if dep["name"] == "ceph-csi-operator":
            return dep["version"]
    return None


def main() -> int:
    errors = []
    charts = {p.parent.name: yaml.safe_load(p.read_text()) for p in sorted(CHARTS.glob("*/Chart.yaml"))}

    for field in ("version", "kubeVersion"):
        seen = {name: meta.get(field) for name, meta in charts.items()}
        if len(set(seen.values())) > 1:
            errors.append(f"charts disagree on {field}: {seen}")

    for key in sorted(set(PINS.values())):
        seen = {name: meta.get("annotations", {}).get(key) for name, meta in charts.items()}
        if None in seen.values() or len(set(seen.values())) > 1:
            errors.append(f"charts disagree on annotation {key}: {seen}")

    for name, meta in charts.items():
        for dep in meta.get("dependencies", []):
            key = PINS.get(dep["name"])
            if key is None:
                errors.append(f"{name}: no annotation is defined for dependency {dep['name']}")
                continue
            if dep["version"] != meta.get("annotations", {}).get(key):
                errors.append(f"{name}: {dep['name']} {dep['version']} does not match {key}")
            if dep["name"] == "rook-ceph":
                bundled = bundled_csi_operator(CHARTS / name, dep["version"])
                want = meta.get("annotations", {}).get(PINS["ceph-csi-drivers"])
                if bundled is None:
                    errors.append(f"{name}: cannot read the vendored rook-ceph {dep['version']} archive")
                elif bundled != want:
                    errors.append(f"{name}: rook-ceph bundles ceph-csi-operator {bundled}, annotations say {want}")

    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
