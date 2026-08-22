#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
hermes_commit="433a8f9fc69a078eb430dab01285d7644e78eb07"
clone_dir="${TMPDIR:-/tmp}/ccsds_hermes_v4.0.11_433a8f9"

if [[ ! -d "$clone_dir/.git" ]]; then
  git clone --quiet --branch v4.0.11 --depth 1 https://github.com/nasa/hermes.git "$clone_dir"
fi

actual_commit=$(git -C "$clone_dir" rev-parse HEAD)
if [[ "$actual_commit" != "$hermes_commit" ]]; then
  echo "Pinned Hermes checkout mismatch: expected $hermes_commit, got $actual_commit" >&2
  exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/ccsds_hermes_work.XXXXXX")
(
  cd "$work_dir"
  go work init "$script_dir" "$clone_dir"
)

cd "$app_dir"
mix compile

mix run --no-compile --no-start "$script_dir/generate_cases.exs" |
  (cd "$script_dir" && GOWORK="$work_dir/go.work" go run .) |
  mix run --no-compile --no-start "$script_dir/verify_results.exs"
