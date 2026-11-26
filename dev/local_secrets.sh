#!/usr/bin/env bash
# Add missing per-worktree credentials without displaying or replacing existing values.
set -euo pipefail
cd "$(dirname "$0")/.."
file=mise.local.toml
if ! git check-ignore -q "$file" || [ -n "$(git ls-files -- "$file")" ]; then
  echo "$file must be ignored and untracked" >&2
  exit 1
fi
umask 077
if [ ! -f "$file" ]; then printf '[env]\n' > "$file"; fi
chmod 600 "$file"
if ! grep -q '^\[env\]' "$file"; then
  { printf '[env]\n'; cat "$file"; } > "$file.tmp"
  mv "$file.tmp" "$file"
fi
for key in CADENCE_ADMIN_PASSWORD E2E_PERSONA_PASSWORD EARENDIL_DEMO_PROVIDER_TOKEN CADENCE_ERLANG_COOKIE; do
  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$file"; then continue; fi
  value=$(openssl rand -hex 24)
  awk -v line="${key} = \"${value}\"" '{print} !done && /^\[env\]/ {print line; done=1}' "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
done
chmod 600 "$file"
echo "$file: credentials ready (values hidden)"
