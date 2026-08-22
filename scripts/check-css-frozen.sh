#!/bin/sh
# Block commits that add lines to CSS files unless the commit message
# contains [css]. This prevents accidental CSS growth — the HUD utility
# layer and component overrides are a closed set ported from legacy.
# New pages should compose from daisyUI + Tailwind + existing utilities.

css_additions=$(git diff --cached --numstat -- '*.css' | awk '{sum += $1} END {print sum+0}')

if [ "$css_additions" -gt 0 ]; then
  echo ""
  echo "ERROR: CSS files have $css_additions added lines."
  echo ""
  echo "The CSS utility layer is frozen. New pages should compose from"
  echo "daisyUI classes + Tailwind utilities + existing HUD utilities."
  echo ""
  echo "If this CSS change is intentional, include [css] in your commit message"
  echo "and re-commit, or set HK=0 to skip hooks."
  echo ""
  exit 1
fi
