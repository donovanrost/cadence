// Heroicons Tailwind plugin.
//
// Adds `hero-<icon-name>` utility classes (and -solid, -mini, -micro variants)
// that mask locally vendored Heroicons v2.2.0 SVGs as CSS backgrounds.
// See README.md and LICENSE.heroicons for provenance.

/** @type {unknown} */
const pluginExport = require("tailwindcss/plugin");
if (typeof pluginExport !== "function") throw new Error("Expected the Tailwind plugin factory");
// Tailwind's CommonJS build exports the function directly; its declaration uses an ESM default.
const plugin = /** @type {typeof import("tailwindcss/plugin").default} */ (pluginExport);
const icons = require("./heroicons.json");
module.exports = plugin(function (api) {
  const values = Object.fromEntries(Object.keys(icons).map((name) => [name, name]));
  api.matchComponents(
    {
      hero: (name) => {
        /** @type {unknown} */
        const content = Reflect.get(icons, name);
        if (typeof content !== "string") throw new Error(`Unknown Heroicon ${name}`);
        /** @type {unknown} */
        const size = api.theme("spacing.6");
        if (typeof size !== "string") throw new Error("Heroicon spacing must be a CSS length");
        return {
          [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
          "-webkit-mask": `var(--hero-${name})`,
          mask: `var(--hero-${name})`,
          "mask-repeat": "no-repeat",
          "background-color": "currentColor",
          "vertical-align": "middle",
          display: "inline-block",
          width: size,
          height: size,
        };
      },
    },
    { values },
  );
});
