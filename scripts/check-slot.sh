#!/usr/bin/env bash
# Run one heavy-ish check (a vue-tsc, a mix compile / architecture check, one test file) in one of
# a few shared slots, under nice, so ~12 agents on one 8-core machine don't stall each other
# (director, 2026-11-13). Full suites, builds and parallel runs stay gated on load; this is for
# single targeted processes.
#
#   scripts/check-slot.sh <command> [args...]
#   CHECK_SLOTS=3 (default) · CHECK_SLOT_DIR=/tmp/apogee-check-slots
#
# A slot is a directory created with mkdir (atomic). It holds the owner's pid; a slot whose pid is
# gone is reclaimed. The command's own exit status is returned.
set -u
slots="${CHECK_SLOTS:-3}"
dir="${CHECK_SLOT_DIR:-/tmp/apogee-check-slots}"
mkdir -p "$dir"
if [ "$#" -eq 0 ]; then
  echo "usage: scripts/check-slot.sh <command> [args...]" >&2
  exit 2
fi

held=""
release() { [ -n "$held" ] && rm -rf "$held"; }
trap release EXIT INT TERM

waited=0
while [ -z "$held" ]; do
  for i in $(seq 1 "$slots"); do
    slot="$dir/slot-$i"
    if mkdir "$slot" 2>/dev/null; then
      echo "$$ $(whoami) $(date -u +%H:%M:%SZ) $*" >"$slot/owner"
      held="$slot"
      break
    fi
    # Reclaim a slot whose owner died without releasing it.
    pid=$(cut -d' ' -f1 "$slot/owner" 2>/dev/null || true)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$slot"; fi
  done
  if [ -z "$held" ]; then
    [ "$waited" -eq 0 ] && echo "check-slot: all $slots slots busy; waiting…" >&2
    waited=1
    sleep 10
  fi
done

nice -n 10 "$@"
