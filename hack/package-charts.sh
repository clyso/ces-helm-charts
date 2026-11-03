#!/usr/bin/env bash
# Package each chart whose version has no release yet, for the release
# workflow (.github/workflows/charts.yaml), which publishes the packages as
# GitHub releases and adds them to the chart repository's index.
#
#   hack/package-charts.sh <directory>
#
# A release is tagged <chart>-<version>. A chart that already has its tag must
# be unchanged since then, apart from its tests and its schema source: a
# changed chart needs a new version, or the chart in git and the published
# package would differ under one version.
#
# The subcharts must be in place (hack/fetch-subcharts.sh); they go into the
# packages, so installing from the repository fetches nothing from upstream.
# With SIGNING_KEY set, each package is signed with that key from
# SIGNING_KEYRING, whose passphrase is in SIGNING_PASSPHRASE_FILE, and gets a
# .prov file beside it. When GITHUB_OUTPUT is set, count=<packages made> is
# written there.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="${1:?usage: hack/package-charts.sh <directory>}"
mkdir -p "$dest"
dest="$(cd "$dest" && pwd)"
cd "$ROOT"

sign=()
if [[ -n "${SIGNING_KEY:-}" ]]; then
  sign=(--sign --key "$SIGNING_KEY" --keyring "${SIGNING_KEYRING:?}"
        --passphrase-file "${SIGNING_PASSPHRASE_FILE:?}")
fi

count=0
for chart_yaml in charts/*/Chart.yaml; do
  chart="$(dirname "$chart_yaml")"
  name="$(basename "$chart")"
  version="$(python3 -I -c 'import sys, yaml; print(yaml.safe_load(open(sys.argv[1]))["version"])' "$chart_yaml")"
  tag="$name-$version"
  if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null; then
    if ! git diff --quiet "$tag" HEAD -- "$chart" \
        ":(exclude)$chart/tests" ":(exclude)$chart/values.schema.yaml"; then
      echo "$chart changed since $tag, but its version is still $version" >&2
      exit 1
    fi
    echo "$tag: released already"
    continue
  fi
  helm package "$chart" --destination "$dest" "${sign[@]}"
  count=$((count + 1))
done

echo "$count chart(s) packaged into $dest"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "count=$count" >>"$GITHUB_OUTPUT"
fi
