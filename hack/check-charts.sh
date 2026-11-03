#!/usr/bin/env bash
# Offline checks for the Clyso charts in charts/. Nothing here talks to a
# cluster: helm runs with KUBECONFIG=/dev/null, so lookup() returns nothing.
#
#   hack/check-charts.sh               every chart
#   hack/check-charts.sh <chart>...    only these (directory names in charts/)
#
# First each chart's subcharts are fetched if missing and compared with its
# dependencies.sha256 (hack/fetch-subcharts.sh). Then, for each chart:
#   1. values.schema.json must match values.schema.yaml (hack/gen-schemas.py)
#   2. render each tests/*.yaml case and compare with its expectations; lint
#      the chart (helm lint --strict) with the values of every passing case
#
# A test case is a values file whose leading comment block sets expectations:
#   # namespace: storage-system     release namespace (default: rook-ceph)
#   # kube-version: 1.31.0          (default: 1.35.0)
#   # expect-error: <regex>         rendering must fail with a matching message
#   # expect: <regex>               the output must match (repeatable)
#   # reject: <regex>               the output must not match (repeatable)
# Regexes are POSIX extended. They see the output with line breaks turned into
# spaces, so one regex can cover a `- name:` and `value:` pair.
#
# Needs helm 3.13 or later, and python3 with PyYAML.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KUBECONFIG=/dev/null
DEFAULT_KUBE_VERSION=1.35.0
DEFAULT_NAMESPACE=rook-ceph
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

log() { printf '%s\n' "$*"; }
bad() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
indent() { sed 's/^/    /' "$1" >&2; }

# header <file> <key>: the values of "# <key>: <value>" lines in the leading
# comment block, one per line.
header() {
  awk -v key="$2" '
    !/^#/ { exit }
    { line = $0; sub(/^# ?/, "", line)
      if (index(line, key ": ") == 1) print substr(line, length(key) + 3) }' "$1"
}

# check_re <case> <expect|reject> <regex>: one expectation against the
# flattened output. grep exits 2 on a regex it cannot compile, which must fail
# the case rather than pass as "no match".
check_re() {
  local case="$1" kind="$2" re="$3" rc=0
  grep -Eq -- "$re" "$WORK/flat" 2>"$WORK/grep" || rc=$?
  if (( rc > 1 )); then
    bad "$case: invalid regex /$re/: $(<"$WORK/grep")"
  elif [[ "$kind" == expect ]] && (( rc != 0 )); then
    bad "$case: output does not match /$re/"
  elif [[ "$kind" == reject ]] && (( rc == 0 )); then
    bad "$case: output matches /$re/"
  fi
}

check_schema() {
  local chart="$1"
  [[ -f "$chart/values.schema.yaml" ]] || return 0
  python3 -I "$ROOT/hack/gen-schemas.py" --check "$chart" || bad "$chart: stale values.schema.json"
}

run_case() {
  local chart="$1" case="$2" ns kv expect_error re
  # header() reads only the leading comment block, so a directive after a blank
  # line would be skipped without a word.
  if awk '!/^#/ { body = 1; next }
          body && /^# ?(namespace|kube-version|expect-error|expect|reject): / { found = 1; exit }
          END { exit !found }' "$case"; then
    bad "$case: a directive after the leading comment block would be ignored"
  fi
  ns="$(header "$case" namespace | tail -n1)"
  kv="$(header "$case" kube-version | tail -n1)"
  expect_error="$(header "$case" expect-error | tail -n1)"
  ns="${ns:-$DEFAULT_NAMESPACE}"
  kv="${kv:-$DEFAULT_KUBE_VERSION}"

  if helm template test "$chart" --namespace "$ns" --kube-version "$kv" -f "$case" \
      >"$WORK/out" 2>"$WORK/err"; then
    if [[ -n "$expect_error" ]]; then
      bad "$case: rendered, but expected an error matching /$expect_error/"
      return
    fi
  else
    if [[ -z "$expect_error" ]]; then
      bad "$case: rendering failed:"
      indent "$WORK/err"
    elif ! grep -Eq -- "$expect_error" "$WORK/err"; then
      bad "$case: the error does not match /$expect_error/:"
      indent "$WORK/err"
    fi
    return
  fi

  tr '\n' ' ' <"$WORK/out" >"$WORK/flat"
  while IFS= read -r re; do check_re "$case" expect "$re"; done < <(header "$case" expect)
  while IFS= read -r re; do check_re "$case" reject "$re"; done < <(header "$case" reject)

  if ! helm lint --strict "$chart" --namespace "$ns" --kube-version "$kv" -f "$case" \
      >"$WORK/lint" 2>&1; then
    bad "$case: helm lint --strict failed:"
    indent "$WORK/lint"
  fi
}

check_chart() {
  local chart="$ROOT/charts/$1" case n=0
  [[ -f "$chart/Chart.yaml" ]] || { bad "no chart at charts/$1"; return; }
  log "charts/$1"
  check_schema "$chart"
  for case in "$chart"/tests/*.yaml; do
    [[ -e "$case" ]] || continue
    run_case "$chart" "$case"
    n=$((n + 1))
  done
  (( n > 0 )) || bad "charts/$1 has no tests/*.yaml cases"
  log "  $n cases"
}

command -v helm >/dev/null || { echo "helm not found" >&2; exit 1; }
python3 -I -c 'import yaml' 2>/dev/null || { echo "python3 with PyYAML required" >&2; exit 1; }

if (( $# )); then
  charts=("$@")
else
  charts=()
  for c in "$ROOT"/charts/*/Chart.yaml; do charts+=("$(basename "$(dirname "$c")")"); done
fi
"$ROOT/hack/fetch-subcharts.sh" "${charts[@]}" || bad "subcharts missing or not matching dependencies.sha256"
for c in "${charts[@]}"; do check_chart "$c"; done

if (( failures )); then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "all checks passed"
