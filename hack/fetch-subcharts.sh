#!/usr/bin/env bash
# Fetch the pinned upstream subcharts into charts/<chart>/charts/ and check
# them: Chart.lock must record exactly the pins of Chart.yaml, under the
# digest Helm computes for them; the archives must match dependencies.sha256;
# and `helm dependency list` must report them all ok. Archives already
# present and matching are not fetched again.
#
#   hack/fetch-subcharts.sh               every chart
#   hack/fetch-subcharts.sh <chart>...    only these (directory names in charts/)
#
# This replaces `helm dependency build`, which refuses any repository that
# was not first added with `helm repo add`. `helm pull --repo` takes the
# version exactly as Chart.lock records it, and dependencies.sha256 then pins
# the archive itself: Rook's index lists 1.21.1 twice, as 1.21.1 and
# v1.21.1, with different archives.
#
# charts/<chart>/charts/ holds nothing but fetched archives (it is
# git-ignored) and is emptied before a fetch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG=/dev/null

# Print the dependencies of the chart directory $1, one "name repository
# version" line each, after checking that its Chart.lock records exactly the
# pins of its Chart.yaml under the digest Helm would compute: the sha256 of
# the JSON of [Chart.yaml dependencies, Chart.lock dependencies], with the
# fields, field order and omitempty rules of Helm's chart.Dependency
# (resolver.HashReq). `helm dependency build` refuses a lock with any other
# digest.
locked() {
  python3 -I -c '
import hashlib, json, sys, yaml

chart = sys.argv[1]
wanted = yaml.safe_load(open(chart + "/Chart.yaml")).get("dependencies") or []
lock = yaml.safe_load(open(chart + "/Chart.lock"))
pinned = lock.get("dependencies") or []

def pin(dep):
    return dep["name"], dep["repository"], str(dep["version"])

if [pin(d) for d in wanted] != [pin(d) for d in pinned]:
    sys.exit(f"{chart}/Chart.lock does not record the dependencies of Chart.yaml")

FIELDS = ["name", "version", "repository", "condition", "tags", "enabled", "import-values", "alias"]
def as_helm(dep):
    return {f: dep[f] for f in FIELDS if f in ("name", "repository") or dep.get(f)}
data = json.dumps([[as_helm(d) for d in wanted], [as_helm(d) for d in pinned]], separators=(",", ":"))
if "sha256:" + hashlib.sha256(data.encode()).hexdigest() != lock.get("digest"):
    sys.exit(f"{chart}/Chart.lock: the digest does not match the dependencies")

for dep in pinned:
    print(*pin(dep))
' "$1"
}

fetch() {
  local chart="$ROOT/charts/$1" deps name repo version
  [[ -f "$chart/Chart.lock" ]] || return 0
  deps="$(locked "$chart")" || return 1
  if ! (cd "$chart" && sha256sum --check --status dependencies.sha256 2>/dev/null); then
    echo "charts/$1: fetching subcharts"
    rm -rf "$chart/charts"
    mkdir -p "$chart/charts"
    # Called as `fetch ... || rc=1`, so set -e is off in here: check each pull,
    # or a failed download would be reported below as a digest mismatch.
    while read -r name repo version; do
      if ! helm pull "$name" --repo "$repo" --version "$version" --destination "$chart/charts"; then
        echo "charts/$1: could not fetch $name $version from $repo" >&2
        return 1
      fi
    done <<<"$deps"
  fi
  if ! (cd "$chart" && sha256sum --check --quiet dependencies.sha256); then
    echo "charts/$1: the subchart archives differ from dependencies.sha256" >&2
    return 1
  fi
  if ! helm dependency list "$chart" | awk 'NR > 1 && NF && $NF != "ok" { bad = 1 } END { exit bad }'; then
    echo "charts/$1: helm dependency list reports subcharts that are not ok:" >&2
    helm dependency list "$chart" >&2
    return 1
  fi
}

command -v helm >/dev/null || { echo "helm not found" >&2; exit 1; }
python3 -I -c 'import yaml' 2>/dev/null || { echo "python3 with PyYAML required" >&2; exit 1; }

if (( $# )); then
  charts=("$@")
else
  charts=()
  for c in "$ROOT"/charts/*/Chart.yaml; do charts+=("$(basename "$(dirname "$c")")"); done
fi
rc=0
for c in "${charts[@]}"; do fetch "$c" || rc=1; done
exit "$rc"
