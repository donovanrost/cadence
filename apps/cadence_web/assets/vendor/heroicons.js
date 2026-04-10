// Heroicons Tailwind plugin.
//
// Adds `hero-<icon-name>` utility classes (and -solid, -mini, -micro variants)
// that mask heroicon SVGs as CSS backgrounds. Reads the SVGs from the
// tailwindlabs/heroicons Mix dep installed at deps/heroicons/optimized.

const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function({matchComponents, theme}) {
  const iconsDir = path.join(__dirname, "../../../../deps/heroicons/optimized")
  const values = {}
  const icons = [
    ["", "/24/outline"],
    ["-solid", "/24/solid"],
    ["-mini", "/20/solid"],
    ["-micro", "/16/solid"]
  ]

  icons.forEach(([suffix, dir]) => {
    fs.readdirSync(path.join(iconsDir, dir)).forEach(file => {
      const name = path.basename(file, ".svg") + suffix
      values[name] = {name, fullPath: path.join(iconsDir, dir, file)}
    })
  })

  matchComponents(
    {
      hero: ({name, fullPath}) => {
        const content = fs
          .readFileSync(fullPath)
          .toString()
          .replace(/\r?\n|\r/g, "")
        const size = theme("spacing.6")
        return {
          [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
          "-webkit-mask": `var(--hero-${name})`,
          mask: `var(--hero-${name})`,
          "mask-repeat": "no-repeat",
          "background-color": "currentColor",
          "vertical-align": "middle",
          display: "inline-block",
          width: size,
          height: size
        }
      }
    },
    {values}
  )
})
