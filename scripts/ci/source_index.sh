#!/usr/bin/env bash
# Keeps a restored _build cache incremental across fresh checkouts.
#
# actions/checkout gives every file a new mtime. Mix then sees config/*.exs as newer than the
# cached manifests, compares the compile-time config, and recompiles a whole project when its
# own app's config differs. apps/cadence's test config embeds System.pid() and
# MIX_TEST_PARTITION, so it always differs, and every job recompiled all of cadence.
#
#   source_index.sh write <index>     record each tracked file's blob SHA (run before saving)
#   source_index.sh backdate <index>  after restoring, give every file whose blob SHA matches the
#                                     index an mtime in 2000, older than any cached artifact
#
# Files changed or added since the index keep their checkout mtime, so Mix sees exactly those
# as modified and recompiles them and their dependents. It's correct by construction: no
# commit-time guessing, so a file merged after the cache was saved is never mistaken for old.
set -euo pipefail
export LC_ALL=C

usage() {
  echo "usage: source_index.sh write|backdate <index>" >&2
  exit 2
}

[ $# -eq 2 ] || usage
command=$1
index=$2

# "<mode> <blob> <stage>\t<path>" per tracked file. Paths git would quote (tabs, newlines,
# quotes) are left out: their files simply keep the checkout mtime and recompile.
tracked() {
  git -c core.quotePath=false ls-files --stage | grep -v $'\t"' | sort
}

case "$command" in
  write)
    mkdir -p "$(dirname "$index")"
    tracked > "$index"
    echo "Source index: $(($(wc -l < "$index"))) tracked files -> $index"
    ;;

  backdate)
    if [ ! -f "$index" ]; then
      echo "No source index at $index (no cache, or one saved before indexing); nothing to backdate."
      exit 0
    fi

    unchanged=$(mktemp)
    comm -12 <(sort "$index") <(tracked) | cut -f2- > "$unchanged"

    if [ -s "$unchanged" ]; then
      tr '\n' '\0' < "$unchanged" | xargs -0 touch -h -t 200001010000 --
    fi

    total=$(($(tracked | wc -l)))
    kept=$(($(wc -l < "$unchanged")))
    echo "Backdated $kept of $total tracked files; $((total - kept)) changed or new since the cached build keep their checkout mtime."
    ;;

  *)
    usage
    ;;
esac
