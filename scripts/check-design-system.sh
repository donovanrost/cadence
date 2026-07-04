#!/bin/sh
# Design-system conformance lint — WARN-ONLY (Phase 2).
#
# Promotes design-system rules into checks. Non-blocking while the migration
# (Phases 3-5) is in flight; Phase 6 flips these to errors and retires the
# blunt check-css-frozen.sh guard. Run from the repo root.

WEB="apps/cadence_web/lib/cadence_web"
warn=0

echo "── Design-system lint (warnings only) ──"

# 1. Raw color literals in templates — should use tokens (--color-action, …)
#    or Tailwind/daisyUI classes, never an inline oklch()/hex.
raw_color=$(grep -rnE "oklch\(|#[0-9a-fA-F]{8}\b|#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3,4}\b" "$WEB" --include=*.ex --include=*.heex 2>/dev/null \
  | grep -vE "stroke=|fill=\"(none|currentColor)\"|hero-|&#x?[0-9a-fA-F]+;" || true)
if [ -n "$raw_color" ]; then
  n=$(printf '%s\n' "$raw_color" | wc -l | tr -d ' ')
  echo "⚠  $n raw color literal(s) in templates — use a token or class:"
  printf '%s\n' "$raw_color" | head -6 | sed 's/^/     /'
  warn=$((warn + 1))
fi

# 2. z-index literals — should use the --z-* tier tokens.
zlit=$(grep -rnE "z-\[[0-9]+\]|z-index: *[0-9]" "$WEB" 2>/dev/null || true)
if [ -n "$zlit" ]; then
  n=$(printf '%s\n' "$zlit" | wc -l | tr -d ' ')
  echo "⚠  $n z-index literal(s) — use --z-* (popover/modal/toast/tooltip):"
  printf '%s\n' "$zlit" | head -6 | sed 's/^/     /'
  warn=$((warn + 1))
fi

# 3. Raw form inputs — should use <.input> from FormInputs.
rawin=$(grep -rnE "<input |<select |<textarea " "$WEB" --include=*.heex 2>/dev/null \
  | grep -v 'type="hidden"' || true)
if [ -n "$rawin" ]; then
  n=$(printf '%s\n' "$rawin" | wc -l | tr -d ' ')
  echo "⚠  $n raw form input(s) — use <.input>:"
  printf '%s\n' "$rawin" | head -6 | sed 's/^/     /'
  warn=$((warn + 1))
fi

# 4. Tailwind `uppercase` utility — bypasses --label-case, so the legibility
#    skin can't un-uppercase it. Use hud-label (or a class wired to the knob).
upc=$(grep -rnE 'class="[^"]*\buppercase\b' "$WEB" --include=*.ex --include=*.heex 2>/dev/null || true)
if [ -n "$upc" ]; then
  n=$(printf '%s\n' "$upc" | wc -l | tr -d ' ')
  echo "⚠  $n Tailwind uppercase utilit(ies) — bypasses --label-case (legibility skin):"
  printf '%s\n' "$upc" | head -6 | sed 's/^/     /'
  warn=$((warn + 1))
fi

# 5. Design-system card drift — card oklch literals must mirror authored CSS.
if command -v node >/dev/null 2>&1; then
  node scripts/check-card-drift.mjs | tail -2 | head -1
fi

if [ "$warn" -eq 0 ]; then
  echo "✓ no design-system violations"
fi
echo "── warn-only; does not block. Phase 6 flips to error. ──"
exit 0
