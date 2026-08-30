<script setup lang="ts">
const structureTokens = [
  "--cadence-color-canvas",
  "--cadence-color-surface",
  "--cadence-color-surface-inset",
  "--cadence-color-border",
  "--cadence-color-text-strong",
  "--cadence-color-text-muted",
] as const;

const signalTokens = [
  ["ACTION", "--cadence-color-accent", "Commit, selection, and primary interaction"],
  ["LIVE", "--cadence-color-signal", "Live data, focus, and active telemetry"],
  ["NOMINAL", "--cadence-color-success", "Confirmed successful or nominal state"],
  ["ATTENTION", "--cadence-color-warning", "A condition that requires attention"],
  ["IMMEDIATE", "--cadence-color-danger", "Failure, danger, or immediate consequence"],
] as const;

const spacingTokens = [
  "--cadence-space-1",
  "--cadence-space-2",
  "--cadence-space-3",
  "--cadence-space-4",
  "--cadence-space-6",
  "--cadence-space-8",
  "--cadence-space-12",
  "--cadence-space-16",
] as const;

const principles = [
  ["01", "Structure is binary", "White lines in dark mode. Black lines in light mode."],
  ["02", "Color has a job", "Chroma identifies state, action, selection, or live signal."],
  ["03", "Every edge is square", "Zero radius. No pills, soft cards, or simulated hardware."],
  ["04", "Depth is hierarchy", "Spacing, alignment, and contrast replace shadows and elevation."],
] as const;
</script>

<template>
  <main class="token-reference">
    <header class="system-header">
      <div class="system-line">
        <span>CADENCE / VISUAL FOUNDATIONS</span>
        <span>GEN 02 / WORKING DIRECTION</span>
      </div>
      <div class="hero-grid">
        <div>
          <p class="eyebrow">Operational monochrome</p>
          <h1>Structure first.<br />Signal only when it means something.</h1>
        </div>
        <p class="hero-copy">
          A spacecraft-operations interface built from hard boundaries, exact alignment, and
          machine-readable evidence. The surface is monochrome. Color is information.
        </p>
      </div>
      <dl class="system-facts">
        <div>
          <dt>Modes</dt>
          <dd>Dark / Light</dd>
        </div>
        <div>
          <dt>Primary line</dt>
          <dd>1 px</dd>
        </div>
        <div>
          <dt>Corner radius</dt>
          <dd>0 px</dd>
        </div>
        <div>
          <dt>Elevation</dt>
          <dd>None</dd>
        </div>
      </dl>
    </header>

    <section class="foundation-section" aria-labelledby="principles-title">
      <div class="section-heading">
        <p>00 / SYSTEM RULES</p>
        <h2 id="principles-title">The constraints are the identity.</h2>
      </div>
      <div class="principle-grid">
        <article v-for="[index, title, description] in principles" :key="index">
          <span>{{ index }}</span>
          <div>
            <h3>{{ title }}</h3>
            <p>{{ description }}</p>
          </div>
        </article>
      </div>
    </section>

    <section class="foundation-section" aria-labelledby="structure-title">
      <div class="section-heading">
        <p>01 / STRUCTURE</p>
        <h2 id="structure-title">Monochrome carries the frame.</h2>
      </div>
      <div class="structure-grid">
        <article v-for="token in structureTokens" :key="token">
          <div class="structure-swatch" :style="{ background: `var(${token})` }"></div>
          <code>{{ token }}</code>
        </article>
      </div>
    </section>

    <section class="foundation-section" aria-labelledby="signal-title">
      <div class="section-heading">
        <p>02 / SEMANTIC COLOR</p>
        <h2 id="signal-title">No decorative chroma.</h2>
      </div>
      <div class="signal-ledger">
        <article v-for="[label, token, meaning] in signalTokens" :key="token">
          <span class="signal-mark" :style="{ background: `var(${token})` }"></span>
          <strong>{{ label }}</strong>
          <code>{{ token }}</code>
          <p>{{ meaning }}</p>
        </article>
      </div>
    </section>

    <section class="foundation-section" aria-labelledby="type-title">
      <div class="section-heading">
        <p>03 / TYPE</p>
        <h2 id="type-title">Interface voice. Evidence voice.</h2>
      </div>
      <div class="type-grid">
        <article class="type-interface">
          <header><span>INTERFACE</span><code>Archivo Variable</code></header>
          <p>CONTACT WINDOW<br />OPENS IN 08:38</p>
          <small>Navigation, hierarchy, instructions, and actions.</small>
        </article>
        <article class="type-data">
          <header><span>EVIDENCE</span><code>JetBrains Mono Variable</code></header>
          <p>APID 0205<br />184:14:23:02 MET<br />C/N₀ 48.2 dB-Hz</p>
          <small>Time, values, units, identifiers, coordinates, and commands.</small>
        </article>
      </div>
    </section>

    <section class="foundation-section foundation-section--split" aria-labelledby="space-title">
      <div>
        <div class="section-heading section-heading--stacked">
          <p>04 / SPACING</p>
          <h2 id="space-title">A four-pixel working rhythm.</h2>
        </div>
        <div class="space-list">
          <article v-for="token in spacingTokens" :key="token">
            <code>{{ token }}</code>
            <div><span :style="{ width: `var(${token})` }"></span></div>
          </article>
        </div>
      </div>
      <div>
        <div class="section-heading section-heading--stacked">
          <p>05 / GEOMETRY</p>
          <h2>Hard edges. Flat layers.</h2>
        </div>
        <div class="geometry-grid" aria-label="Geometry rules">
          <article><span>RADIUS</span><strong>0</strong><code>ALL SURFACES</code></article>
          <article><span>SHADOW</span><strong>0</strong><code>ALL LAYERS</code></article>
          <article><span>PRIMARY</span><strong>1</strong><code>PX SOLID LINE</code></article>
          <article><span>FOCUS</span><strong>2</strong><code>PX SIGNAL OUTLINE</code></article>
        </div>
      </div>
    </section>

    <footer>
      <span>CAD / DS / G02</span>
      <p>Working visual direction. Semantic meaning remains governed by the state model.</p>
    </footer>
  </main>
</template>

<style scoped>
.token-reference {
  width: min(1440px, 100%);
  min-height: 100vh;
  margin: 0 auto;
  padding: clamp(24px, 4vw, 64px);
}

.system-header {
  border: 1px solid var(--cadence-color-border);
}

.system-line {
  display: flex;
  justify-content: space-between;
  gap: var(--cadence-space-4);
  padding: var(--cadence-space-2) var(--cadence-space-3);
  border-bottom: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text-secondary);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

.hero-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.5fr) minmax(260px, 0.5fr);
  gap: clamp(32px, 7vw, 112px);
  align-items: end;
  min-height: min(62vh, 680px);
  padding: clamp(32px, 7vw, 104px);
}

.eyebrow,
.section-heading > p,
.token-reference code,
.token-reference footer span,
.type-grid header,
.geometry-grid span,
.geometry-grid code {
  margin: 0;
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
  text-transform: uppercase;
}

.hero-grid h1 {
  max-width: 980px;
  margin: var(--cadence-space-6) 0 0;
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-display);
  font-size: var(--cadence-type-display-xl);
  font-weight: 670;
  letter-spacing: var(--cadence-tracking-display);
  line-height: var(--cadence-leading-tight);
  text-transform: uppercase;
}

.hero-copy {
  margin: 0;
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-md);
  line-height: var(--cadence-leading-copy);
}

.system-facts {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  margin: 0;
  border-top: 1px solid var(--cadence-color-border);
}

.system-facts div {
  display: grid;
  gap: var(--cadence-space-2);
  padding: var(--cadence-space-4);
  border-left: 1px solid var(--cadence-color-border);
}

.system-facts div:first-child {
  border-left: 0;
}

.system-facts dt {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
  text-transform: uppercase;
}

.system-facts dd {
  margin: 0;
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-body-sm);
}

.foundation-section {
  padding: clamp(64px, 9vw, 120px) 0;
  border-top: 1px solid var(--cadence-color-border);
}

.system-header + .foundation-section {
  margin-top: clamp(64px, 10vw, 144px);
}

.section-heading {
  display: grid;
  grid-template-columns: minmax(180px, 0.32fr) 1fr;
  gap: var(--cadence-space-8);
  margin-bottom: clamp(32px, 5vw, 64px);
}

.section-heading h2 {
  max-width: 820px;
  margin: -7px 0 0;
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-title-lg);
  font-weight: 650;
  letter-spacing: -0.025em;
  line-height: 1.05;
  text-transform: uppercase;
}

.section-heading--stacked {
  display: block;
}

.section-heading--stacked > p {
  margin-bottom: var(--cadence-space-4);
}

.principle-grid,
.structure-grid,
.signal-ledger,
.type-grid,
.geometry-grid {
  border-top: 1px solid var(--cadence-color-border);
  border-left: 1px solid var(--cadence-color-border);
}

.principle-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
}

.principle-grid article {
  display: flex;
  min-height: 250px;
  padding: var(--cadence-space-5);
  flex-direction: column;
  justify-content: space-between;
  border-right: 1px solid var(--cadence-color-border);
  border-bottom: 1px solid var(--cadence-color-border);
}

.principle-grid article > span {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: var(--cadence-type-label);
}

.principle-grid h3 {
  margin: 0 0 var(--cadence-space-3);
  color: var(--cadence-color-text-strong);
  font-size: 1rem;
  text-transform: uppercase;
}

.principle-grid p {
  margin: 0;
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
  line-height: var(--cadence-leading-copy);
}

.structure-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.structure-grid article {
  border-right: 1px solid var(--cadence-color-border);
  border-bottom: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-surface);
}

.structure-swatch {
  height: 128px;
  border-bottom: 1px solid var(--cadence-color-border);
}

.structure-grid code {
  display: block;
  overflow: hidden;
  padding: var(--cadence-space-3);
  color: var(--cadence-color-text-secondary);
  letter-spacing: 0;
  text-overflow: ellipsis;
  text-transform: none;
  white-space: nowrap;
}

.signal-ledger article {
  display: grid;
  grid-template-columns: 16px minmax(92px, 0.18fr) minmax(250px, 0.42fr) 1fr;
  align-items: center;
  gap: var(--cadence-space-4);
  min-height: 72px;
  padding: var(--cadence-space-3) var(--cadence-space-4);
  border-right: 1px solid var(--cadence-color-border);
  border-bottom: 1px solid var(--cadence-color-border);
}

.signal-mark {
  width: 12px;
  height: 12px;
}

.signal-ledger strong {
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-body-sm);
  letter-spacing: var(--cadence-tracking-label);
}

.signal-ledger code {
  letter-spacing: 0;
  text-transform: none;
}

.signal-ledger p {
  margin: 0;
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
}

.type-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.type-grid article {
  display: flex;
  min-height: 390px;
  padding: clamp(24px, 4vw, 48px);
  flex-direction: column;
  border-right: 1px solid var(--cadence-color-border);
  border-bottom: 1px solid var(--cadence-color-border);
}

.type-grid header {
  display: flex;
  justify-content: space-between;
  gap: var(--cadence-space-4);
}

.type-grid header code {
  letter-spacing: 0;
  text-transform: none;
}

.type-grid p {
  margin: auto 0 var(--cadence-space-8);
  color: var(--cadence-color-text-strong);
}

.type-interface p {
  font-size: clamp(2.25rem, 5vw, 4.75rem);
  font-weight: 680;
  letter-spacing: -0.045em;
  line-height: 0.95;
}

.type-data p {
  font-family: var(--cadence-font-mono);
  font-size: clamp(1.25rem, 2.5vw, 2.25rem);
  line-height: 1.65;
}

.type-grid small {
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
  line-height: var(--cadence-leading-copy);
}

.foundation-section--split {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: clamp(48px, 8vw, 120px);
}

.space-list {
  border-top: 1px solid var(--cadence-color-border);
}

.space-list article {
  display: grid;
  grid-template-columns: 160px 1fr;
  align-items: center;
  min-height: 52px;
  border-bottom: 1px solid var(--cadence-color-border);
}

.space-list code {
  color: var(--cadence-color-text-secondary);
  letter-spacing: 0;
  text-transform: none;
}

.space-list article > div {
  display: flex;
  align-items: center;
  height: 18px;
}

.space-list article > div span {
  display: block;
  height: 100%;
  min-width: 4px;
  background: var(--cadence-color-border);
}

.geometry-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}

.geometry-grid article {
  display: flex;
  min-height: 150px;
  padding: var(--cadence-space-4);
  flex-direction: column;
  justify-content: space-between;
  border-right: 1px solid var(--cadence-color-border);
  border-bottom: 1px solid var(--cadence-color-border);
}

.geometry-grid strong {
  color: var(--cadence-color-text-strong);
  font-family: var(--cadence-font-mono);
  font-size: 3rem;
  font-weight: 400;
}

footer {
  display: flex;
  justify-content: space-between;
  gap: var(--cadence-space-8);
  padding: var(--cadence-space-5) 0;
  border-top: 1px solid var(--cadence-color-border);
}

footer p {
  max-width: 560px;
  margin: 0;
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
  text-align: right;
}

@media (width <= 900px) {
  .hero-grid,
  .foundation-section--split {
    grid-template-columns: 1fr;
  }

  .hero-grid {
    min-height: auto;
  }

  .system-facts,
  .principle-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .structure-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .signal-ledger article {
    grid-template-columns: 16px 1fr;
  }
}

@media (width <= 640px) {
  .system-line,
  footer {
    align-items: flex-start;
    flex-direction: column;
  }

  .section-heading,
  .system-facts,
  .principle-grid,
  .structure-grid,
  .type-grid,
  .geometry-grid {
    grid-template-columns: 1fr;
  }

  .section-heading > p {
    margin-bottom: var(--cadence-space-3);
  }

  .system-facts div {
    border-top: 1px solid var(--cadence-color-border);
    border-left: 0;
  }

  .system-facts div:first-child {
    border-top: 0;
  }

  .signal-ledger article {
    grid-template-columns: 16px 1fr;
  }

  .signal-ledger article p,
  .signal-ledger article code {
    grid-column: 2;
  }

  footer p {
    text-align: left;
  }
}
</style>
