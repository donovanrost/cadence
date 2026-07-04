// WCAG 2.x contrast audit driven by the shipped CSS.
// Parses tokens.css / app.css / component-overrides.css / hud-system.css and
// resolves var() + relative oklch() syntax, so it audits what the app actually
// renders — change a token and this picks it up. Run from the repo root:
//   node scripts/contrast-check.mjs

import { readFileSync } from "node:fs";

const FILES = {
  tokens: "apps/cadence_web/assets/css/tokens.css",
  app: "apps/cadence_web/assets/css/app.css",
  overrides: "apps/cadence_web/assets/css/components/component-overrides.css",
  hud: "apps/cadence_web/assets/css/components/hud-system.css",
};
const src = Object.fromEntries(
  Object.entries(FILES).map(([k, p]) => [k, readFileSync(p, "utf8")])
);

// ---- custom-property map. First declaration wins: tokens.css is the source
// of truth, and later app.css blocks ([data-skin="legible"]) must not override.
const props = new Map();
for (const css of [src.tokens, src.app]) {
  for (const m of css.matchAll(/--([\w-]+)\s*:\s*([^;]+);/g)) {
    if (!props.has(m[1])) props.set(m[1], m[2].trim());
  }
}

// ---- CSS value resolver → { L, C, H, alpha } in oklch space ----
function resolveValue(value, depth = 0) {
  if (depth > 12) throw new Error(`var() cycle resolving: ${value}`);
  value = value.trim();

  let m = value.match(/^var\(--([\w-]+)\)$/);
  if (m) {
    const v = props.get(m[1]);
    if (!v) throw new Error(`undefined custom property --${m[1]}`);
    return resolveValue(v, depth + 1);
  }

  m = value.match(
    /^oklch\(\s*from\s+(var\(--[\w-]+\)|oklch\([^()]*\))\s+(\S+)\s+(\S+)\s+([^\s/)]+)\s*(?:\/\s*([\d.]+%?))?\s*\)$/
  );
  if (m) {
    const base = resolveValue(m[1], depth + 1);
    const comp = (tok, key) => {
      if (tok === "l" || tok === "c" || tok === "h") return base[tok.toUpperCase()];
      const vm = tok.match(/^var\(--([\w-]+)\)$/);
      if (vm) return parseFloat(props.get(vm[1]));
      if (tok.endsWith("%")) return parseFloat(tok) / 100;
      return parseFloat(tok);
    };
    return {
      L: comp(m[2]),
      C: comp(m[3]),
      H: comp(m[4]),
      alpha: m[5] ? parseAlpha(m[5]) : base.alpha,
    };
  }

  m = value.match(
    /^oklch\(\s*([\d.]+%?)\s+([\d.]+)\s+([\d.]+)\s*(?:\/\s*([\d.]+%?))?\s*\)$/
  );
  if (m) {
    return {
      L: m[1].endsWith("%") ? parseFloat(m[1]) / 100 : parseFloat(m[1]),
      C: parseFloat(m[2]),
      H: parseFloat(m[3]),
      alpha: m[4] ? parseAlpha(m[4]) : 1,
    };
  }

  throw new Error(`cannot resolve CSS value: ${value}`);
}
const parseAlpha = (s) => (s.endsWith("%") ? parseFloat(s) / 100 : parseFloat(s));
const token = (name) => resolveValue(`var(--${name})`);

// ---- pull a declaration out of a selector's block (component-overrides etc.) ----
function block(css, selector) {
  const i = css.indexOf(selector);
  if (i < 0) throw new Error(`selector not found: ${selector}`);
  const open = css.indexOf("{", i);
  return css.slice(open + 1, css.indexOf("}", open));
}
function declColor(blockText, prop) {
  const m = blockText.match(new RegExp(`(?:^|[{;])\\s*${prop}\\s*:\\s*([^;]+)`));
  if (!m) throw new Error(`no ${prop} declaration found`);
  const c = m[1].match(/(oklch\([^;]*?\)|var\(--[\w-]+\))\s*(?:!important)?\s*$/);
  return resolveValue((c ?? m)[1].trim());
}

// ---- color math: oklch -> linear sRGB (gamut-clamped) -> gamma; WCAG luminance ----
const clamp01 = (x) => Math.min(1, Math.max(0, x));
function oklchToLinear({ L, C, H }) {
  const h = (H * Math.PI) / 180;
  const a = C * Math.cos(h), b = C * Math.sin(h);
  const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
  const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
  const s_ = L - 0.0894841775 * a - 1.291485548 * b;
  const l = l_ ** 3, m = m_ ** 3, s = s_ ** 3;
  return [
    clamp01(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    clamp01(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    clamp01(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
  ];
}
const linToGamma = (c) => (c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055);
const gammaToLin = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const srgb = (rec) => oklchToLinear(rec).map(linToGamma);
const lumOf = (rgb) => {
  const [r, g, b] = rgb.map(gammaToLin);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (c1, c2) => {
  const l1 = lumOf(c1), l2 = lumOf(c2);
  const [hi, lo] = l1 > l2 ? [l1, l2] : [l2, l1];
  return (hi + 0.05) / (lo + 0.05);
};

// ---- resolved palette ----
const S = {
  base100: token("color-base-100"),
  base200: token("color-base-200"),
  base300: token("color-base-300"),
  input: token("surface-input"),
  // telemetry_chart.js paints its own bg/ticks — not tokenized yet (data-viz
  // backlog). Keep the literals here until the chart hook consumes tokens.
  chart: resolveValue("oklch(10% 0.02 265)"),
};
const C = {
  baseContent: token("color-base-content"),
  textSubtle: token("text-subtle"),
  textMuted: token("text-muted"),
  hudLabel: declColor(block(src.hud, ".dark .hud-label"), "color"),
  primary: token("color-primary"),
  stCritical: token("status-critical"),
  stWarning: token("status-warning"),
  stSuccess: token("status-success"),
  stInfo: token("status-info"),
  tick: resolveValue("oklch(82% 0.04 270)"), // telemetry_chart.js, see above
  borderDefault: token("border-default"),
  borderStrong: token("border-strong"),
  inputBorder: declColor(block(src.overrides, '[data-theme="dark"] .input,'), "border"),
};
const badge = (name) => {
  const b = block(src.overrides, `[data-theme="dark"] .badge-${name}`);
  return { bg: declColor(b, "background"), fg: declColor(b, "color") };
};

// ---- audit ----
const rows = [];
const add = (label, fg, bg, { alpha = fg.alpha ?? 1, large = false } = {}) => {
  const bgRGB = srgb(bg);
  let fgRGB = srgb(fg);
  if (alpha < 1) fgRGB = fgRGB.map((c, i) => alpha * c + (1 - alpha) * bgRGB[i]);
  const r = contrast(fgRGB, bgRGB);
  const verdict = large
    ? `(large/UI 3:1) ${r >= 3 ? "PASS" : "fail"}`
    : r >= 4.5 ? "PASS" : "fail";
  rows.push([label, r.toFixed(2), verdict]);
};

// Body / informational text
add("base-content FULL on base-100", C.baseContent, S.base100);
add("base-content FULL on base-200", C.baseContent, S.base200);
add("base-content /70 on base-100", C.baseContent, S.base100, { alpha: 0.7 });
add("base-content /70 on base-200", C.baseContent, S.base200, { alpha: 0.7 });
add("base-content /60 on base-100", C.baseContent, S.base100, { alpha: 0.6 });
add("base-content /60 on base-200", C.baseContent, S.base200, { alpha: 0.6 });
add("base-content /50 on base-100", C.baseContent, S.base100, { alpha: 0.5 });
add("base-content /40 on base-100", C.baseContent, S.base100, { alpha: 0.4 });
// Secondary text tokens
add("text-subtle FULL on base-100", C.textSubtle, S.base100);
add("text-muted FULL on base-100", C.textMuted, S.base100);
add("text-muted FULL on base-200", C.textMuted, S.base200);
add("placeholder (text-muted) on surface-input", C.textMuted, S.input);
// Labels & links
add("hud-label on base-100", C.hudLabel, S.base100);
add("hud-label on base-200", C.hudLabel, S.base200);
add("hud-label on base-300", C.hudLabel, S.base300);
add("primary/link on base-100", C.primary, S.base100);
// Status as text on dark
add("status critical (red) on base-100", C.stCritical, S.base100);
add("status warning (orange) on base-100", C.stWarning, S.base100);
add("status success (green) on base-100", C.stSuccess, S.base100);
add("status info (blue) on base-100", C.stInfo, S.base100);
// Chart tick labels (slate /60 over chart bg)
add("chart tick (slate /60) on chart bg", C.tick, S.chart, { alpha: 0.6, large: true });
// Badge dark variants (text on colored bg)
for (const name of ["error", "warning", "success", "info"]) {
  const { bg, fg } = badge(name);
  add(`badge-${name}: text on fill`, fg, bg);
}
// Borders (3:1 only if they convey state/UI boundary)
add("border-default on base-200", C.borderDefault, S.base200, { large: true });
add("border-strong on base-200", C.borderStrong, S.base200, { large: true });
add("input rest border (dark) on base-200", C.inputBorder, S.base200, { large: true });

// ---- report ----
const pad = (s, n) => (s + " ".repeat(n)).slice(0, n);
const fmt = (r) =>
  `oklch(${(r.L * 100).toFixed(0)}% ${r.C} ${r.H}${r.alpha < 1 ? ` / ${r.alpha}` : ""})`;
console.log("Resolved from CSS (spot-check):");
for (const [n, v] of [
  ["  --text-muted", C.textMuted],
  ["  --status-success", C.stSuccess],
  ["  badge-error bg", badge("error").bg],
  ["  input rest border", C.inputBorder],
])
  console.log(pad(n, 22), fmt(v));
console.log();
console.log(pad("PAIR", 44), pad("RATIO", 8), "VERDICT (normal text AA = 4.5:1)");
console.log("-".repeat(86));
let fails = 0;
for (const [l, r, v] of rows) {
  if (v.includes("fail")) fails++;
  console.log(pad(l, 44), pad(r + ":1", 8), v);
}
console.log("-".repeat(86));
console.log(fails ? `${fails} failing pair(s)` : "all pairs pass");
process.exitCode = 0; // warn-only until Phase 6
