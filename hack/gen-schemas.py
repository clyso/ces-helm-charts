#!/usr/bin/env python3
"""Write each chart's values.schema.json from its values.schema.yaml.

The YAML source carries the comments; Helm reads only the JSON.

    hack/gen-schemas.py                 rewrite every charts/*/values.schema.json
    hack/gen-schemas.py --check         fail if any of them is out of date
    hack/gen-schemas.py charts/<name>   only these chart directories
"""

import argparse
import json
import pathlib
import sys

import yaml

CHARTS = pathlib.Path(__file__).resolve().parent.parent / "charts"


def render(chart: pathlib.Path) -> str:
    schema = yaml.safe_load((chart / "values.schema.yaml").read_text())
    return json.dumps(schema, indent=2) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--check", action="store_true", help="report, do not write")
    ap.add_argument("charts", nargs="*", type=pathlib.Path)
    args = ap.parse_args()

    charts = args.charts or sorted(p.parent for p in CHARTS.glob("*/values.schema.yaml"))
    stale = []
    for chart in charts:
        want = render(chart)
        out = chart / "values.schema.json"
        if out.exists() and out.read_text() == want:
            continue
        if args.check:
            stale.append(out)
        else:
            out.write_text(want)
            print(f"wrote {out}")
    for out in stale:
        print(f"{out} is out of date: run hack/gen-schemas.py", file=sys.stderr)
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
