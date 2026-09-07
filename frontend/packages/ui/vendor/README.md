# Heroicons

`heroicons.json` contains the optimized SVGs from `tailwindlabs/heroicons` **v2.2.0**,
under its MIT license (`LICENSE.heroicons`). The class suffixes preserve the existing Cadence
icon API: outline, `-solid`, `-mini`, and `-micro`.

The Tailwind plugin reads these local assets so frontend package installation and Storybook do
not depend on a Phoenix/Mix checkout. The images are upstream vendor data, not authored components.
To update, run `node frontend/tools/import-heroicons.mjs /path/to/heroicons/optimized` against an
explicitly selected upstream checkout and review the generated JSON and license together.
