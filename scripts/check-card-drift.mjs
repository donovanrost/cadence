// Design-system card drift check — WARN-ONLY.
//
// The cards in apps/cadence_web/design-system/ are self-contained HTML, so
// every oklch() literal in them is a hand-copied mirror of an authored CSS
// value. This script flags mirrors that no longer exist in the authored CSS
// (tokens.css / app.css / components/*.css) — the failure mode that let 52
// stale hue-185 greens survive the green-175 unification.
//
// A literal passes if its base L/C/H triple (alpha ignored) appears anywhere
// in the authored CSS, or in the card-chrome allowlist below (values that are
// part of the cards' own documentation styling, not app mirrors). Near-neutral
// values (chroma <= 0.02 — the cards' slate prose/typography) are skipped, and
// a line containing "ds-allow" is exempt (use it for deliberately non-token
// illustrations, e.g. a proposed palette or a "before" example).
//
// Run from the repo root: node scripts/check-card-drift.mjs

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const CSS_DIR = "apps/cadence_web/assets/css";
const CARD_DIR = "apps/cadence_web/design-system";
const NEUTRAL_CHROMA = 0.02;

// Card-chrome values: the cards' shared documentation template (eyebrows,
// code accents, status markers, do/don't marks) — intentional, not app mirrors.
const CARD_CHROME = [
  "65|0.1|210", // eyebrow / section-label
  "80|0.1|210", // inline <code> accent
  "82|0.05|340", // pink emphasis in ledes
  "85|0.05|340",
  "88|0.05|340",
  "72|0.2|10", // don't-mark red
  "72|0.2|25", // before/don't heading red (choosing-color, content-terminology)
  "80|0.15|50", // "exploring / proposed" status marker
  "76|0.15|285", // "decided" status marker
  "65|0.12|210", // choosing-color "before" panel (documents the old look)
  "82|0.04|270", // chart tick — telemetry_chart.js, not tokenized yet
];

const key = (L, C, H) => `${parseFloat(L)}|${parseFloat(C)}|${parseFloat(H)}`;
const LITERAL = /oklch\(\s*([\d.]+)%\s+([\d.]+)\s+([\d.]+)\s*(?:\/[^)]*)?\)/g;

// ---- truth set: every base triple in the authored CSS ----
const authored = new Set(CARD_CHROME);
const cssFiles = [
  join(CSS_DIR, "tokens.css"),
  join(CSS_DIR, "app.css"),
  ...readdirSync(join(CSS_DIR, "components")).map((f) =>
    join(CSS_DIR, "components", f)
  ),
];
for (const f of cssFiles) {
  for (const m of readFileSync(f, "utf8").matchAll(LITERAL)) {
    authored.add(key(m[1], m[2], m[3]));
  }
}

// ---- scan the cards ----
const cards = [];
for (const dir of readdirSync(CARD_DIR, { withFileTypes: true })) {
  if (!dir.isDirectory()) continue;
  for (const f of readdirSync(join(CARD_DIR, dir.name))) {
    if (f.endsWith(".html")) cards.push(join(CARD_DIR, dir.name, f));
  }
}

let total = 0;
for (const card of cards.sort()) {
  const lines = readFileSync(card, "utf8").split("\n");
  const findings = [];
  lines.forEach((line, i) => {
    if (line.includes("ds-allow")) return;
    for (const m of line.matchAll(LITERAL)) {
      if (parseFloat(m[2]) <= NEUTRAL_CHROMA) continue;
      const k = key(m[1], m[2], m[3]);
      if (!authored.has(k)) findings.push(`  ${i + 1}: ${m[0]}`);
    }
  });
  if (findings.length) {
    total += findings.length;
    console.log(`⚠  ${card}`);
    for (const f of findings) console.log(f);
  }
}

console.log("-".repeat(72));
console.log(
  total
    ? `${total} card literal(s) not found in authored CSS — stale mirror or new card-chrome value (allowlist it if intentional).`
    : "✓ every card literal matches the authored CSS"
);
console.log("── warn-only; does not block. Phase 6 flips to error. ──");
process.exitCode = 0;
