#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
app_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
version="0.32.0"
venv_dir="${TMPDIR:-/tmp}/cadence_ccsds_spacepackets_${version}"

if [[ ! -x "$venv_dir/bin/python" ]]; then
  python3 -m venv "$venv_dir"
  "$venv_dir/bin/pip" install --quiet "spacepackets==${version}"
fi

actual_version=$(
  "$venv_dir/bin/python" -c 'from importlib.metadata import version; print(version("spacepackets"))'
)

if [[ "$actual_version" != "$version" ]]; then
  echo "Pinned spacepackets environment mismatch: expected $version, got $actual_version" >&2
  exit 1
fi

cd "$app_dir"
mix compile

mix run --no-compile --no-start "$script_dir/generate_cases.exs" |
  "$venv_dir/bin/python" "$script_dir/verify.py" |
  mix run --no-compile --no-start "$script_dir/verify_results.exs"
