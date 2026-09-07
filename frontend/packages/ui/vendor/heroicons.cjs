// Heroicons Tailwind plugin.
//
// Adds `hero-<icon-name>` utility classes (and -solid, -mini, -micro variants)
// that mask locally vendored Heroicons v2.2.0 SVGs as CSS backgrounds.
// See README.md and LICENSE.heroicons for provenance.

const plugin = require("tailwindcss/plugin");
const icons = require("./heroicons.json");
module.exports = plugin(function ({ matchComponents, theme }) {
  const values = Object.fromEntries(
    Object.entries(icons).map(([name, content]) => [name, { name, content }]),
  );
  matchComponents(
    {
      hero: ({ name, content }) => {
        const size = theme("spacing.6");
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
