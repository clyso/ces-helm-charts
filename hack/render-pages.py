#!/usr/bin/env python3
"""Write the landing page of the chart repository.

    hack/render-pages.py <index.yaml> <source repository URL> > index.html

Fills in hack/pages/index.html: the charts that <index.yaml> lists, each at
its newest version; the version to install the CES charts at, the newest one
that all three have; and the repository that holds their source. <index.yaml>
may be missing, before the first release.

The page takes the chart repository's own address from wherever it is
served, GitHub Pages or a custom domain, so nothing here depends on it.
"""

import html
import pathlib
import re
import sys

import yaml

TEMPLATE = pathlib.Path(__file__).resolve().parent / "pages" / "index.html"
# The CES charts, in the order they are installed.
CES = ["ces-rook-operator", "ces-csi-drivers", "ces-ceph-cluster"]


def version_key(version: object) -> list[int]:
    return [int(n) for n in re.findall(r"\d+", str(version))]


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    index_path = pathlib.Path(sys.argv[1])
    source = sys.argv[2].rstrip("/")
    index = (yaml.safe_load(index_path.read_text()) if index_path.exists() else None) or {}
    entries = index.get("entries") or {}

    names = [n for n in CES if n in entries] + sorted(n for n in entries if n not in CES)
    rows = []
    for name in names:
        newest = max(entries[name], key=lambda e: version_key(e.get("version")))
        cells = [name, newest.get("version"), newest.get("appVersion"), newest.get("description")]
        text = [html.escape(str(c or "")) for c in cells]
        rows.append(f"<tr><td><code>{text[0]}</code></td><td>{text[1]}</td><td>{text[2]}</td><td>{text[3]}</td></tr>")
    if not rows:
        rows.append('<tr><td colspan="4">No chart has been published yet.</td></tr>')

    shared = None
    for name in CES:
        versions = {str(e.get("version")) for e in entries.get(name, [])}
        shared = versions if shared is None else shared & versions
    ces_version = max(shared, key=version_key) if shared else "<version>"

    fields = {
        "@@CHART_ROWS@@": "\n".join(rows),
        "@@CES_VERSION@@": html.escape(ces_version),
        "@@SOURCE_URL@@": html.escape(source),
        "@@SOURCE_NAME@@": html.escape(source.split("://", 1)[-1]),
        "@@UPDATED@@": html.escape(str(index.get("generated") or "")[:10] or "never"),
    }
    page = TEMPLATE.read_text()
    for field, value in fields.items():
        page = page.replace(field, value)
    left = sorted(set(re.findall(r"@@[A-Z_]+@@", page)))
    if left:
        sys.exit(f"{TEMPLATE}: fields without a value: {', '.join(left)}")
    sys.stdout.write(page)
    return 0


if __name__ == "__main__":
    sys.exit(main())
