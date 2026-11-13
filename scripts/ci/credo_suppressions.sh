#!/usr/bin/env bash
# Credo suppression ratchet: fails when HEAD has more inline `credo:disable-*` comments for any
# check than BASE. `mix credo --strict` is a zero gate, so a suppression comment is the only way
# around it; this keeps that door from widening. Removing suppressions needs no file edit.
#
# Usage: scripts/ci/credo_suppressions.sh <base-rev> [<head-rev>]
# In a pull_request run, HEAD is the PR merge commit, so comparing with the base branch tip
# measures exactly what the PR adds.
set -euo pipefail
export LC_ALL=C

base=${1:?usage: credo_suppressions.sh <base-rev> [<head-rev>]}
head=${2:-HEAD}
paths=(mix.exs apps packages dev)

counts() {
  # Prints "<check> <count>" per suppressed check; a bare disable (no check named) is "*".
  { git grep -h -o -I -E 'credo:disable-for-[a-z-]+(:? *Credo(\.[A-Za-z0-9]+)+)?' "$1" -- "${paths[@]}" || true; } |
    sed -E 's/^credo:disable-for-[a-z-]+:? *//; s/^$/*/' |
    sort | uniq -c | awk '{ print $2, $1 }'
}

base_counts=$(counts "$base")
head_counts=$(counts "$head")

echo "Inline credo suppressions at $head (base $base):"
awk '{ print "  " $0 }' <<<"${head_counts:-none}"

regressions=$(
  join -a 2 -e 0 -o '0,1.2,2.2' <(echo "$base_counts") <(echo "$head_counts") |
    awk '$3 > $2 { printf "%s: %d -> %d\n", $1, $2, $3 }'
)

if [ -n "$regressions" ]; then
  while read -r line; do
    echo "::error title=New credo suppression::$line. Fix the finding instead of disabling the check."
  done <<<"$regressions"
  exit 1
fi

echo "No new suppressions."
