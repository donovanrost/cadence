<script setup lang="ts">
const colorTokens = [
  "--cadence-color-canvas",
  "--cadence-color-shell",
  "--cadence-color-surface-inset",
  "--cadence-color-surface",
  "--cadence-color-surface-raised",
  "--cadence-color-border-subtle",
  "--cadence-color-border",
  "--cadence-color-border-strong",
  "--cadence-color-text",
  "--cadence-color-text-strong",
  "--cadence-color-text-secondary",
  "--cadence-color-text-muted",
  "--cadence-color-accent",
  "--cadence-color-signal",
  "--cadence-color-danger",
] as const;

const spacingTokens = [
  "--cadence-space-1",
  "--cadence-space-2",
  "--cadence-space-3",
  "--cadence-space-4",
  "--cadence-space-5",
  "--cadence-space-6",
  "--cadence-space-8",
] as const;
</script>

<template>
  <main class="token-reference">
    <header class="token-reference__intro">
      <p>CADENCE DESIGN SYSTEM / CURRENT BASELINE</p>
      <h1>Foundations should be visible, comparable, and disposable.</h1>
      <span>
        This reference renders the actual package tokens. Change the source CSS and Storybook
        refreshes every component and foundation specimen together.
      </span>
    </header>

    <section aria-labelledby="color-token-title">
      <div class="token-reference__heading">
        <span>01</span>
        <div>
          <p>SEMANTIC COLOR</p>
          <h2 id="color-token-title">Surfaces, content, and state</h2>
        </div>
      </div>
      <div class="color-grid">
        <article v-for="token in colorTokens" :key="token">
          <div class="color-grid__swatch" :style="{ background: `var(${token})` }"></div>
          <code>{{ token }}</code>
        </article>
      </div>
    </section>

    <section aria-labelledby="type-token-title">
      <div class="token-reference__heading">
        <span>02</span>
        <div>
          <p>TYPOGRAPHY</p>
          <h2 id="type-token-title">Interface and telemetry voices</h2>
        </div>
      </div>
      <div class="type-grid">
        <article>
          <code>--cadence-font-sans</code>
          <p class="type-grid__sans">Mission operations remain legible under pressure.</p>
        </article>
        <article>
          <code>--cadence-font-mono</code>
          <p class="type-grid__mono">APID 0205 · FRAME 184201 · 16.0 HZ</p>
        </article>
      </div>
    </section>

    <section aria-labelledby="space-token-title">
      <div class="token-reference__heading">
        <span>03</span>
        <div>
          <p>SPACING</p>
          <h2 id="space-token-title">A compact, shared rhythm</h2>
        </div>
      </div>
      <div class="space-list">
        <article v-for="token in spacingTokens" :key="token">
          <code>{{ token }}</code>
          <div :style="{ width: `var(${token})` }"></div>
        </article>
      </div>
    </section>
  </main>
</template>

<style scoped>
.token-reference {
  width: min(1180px, 100%);
  min-height: 100vh;
  margin: 0 auto;
  padding: 64px clamp(24px, 6vw, 88px) 96px;
}

.token-reference__intro {
  max-width: 820px;
  margin-bottom: 72px;
}

.token-reference__intro p,
.token-reference__heading p,
.token-reference code {
  margin: 0;
  color: var(--cadence-color-signal);
  font-family: var(--cadence-font-mono);
  font-size: 10px;
  letter-spacing: 0.08em;
}

.token-reference__intro h1 {
  max-width: 760px;
  margin: 12px 0 18px;
  color: var(--cadence-color-text-strong);
  font-size: clamp(34px, 5vw, 64px);
  font-weight: 520;
  letter-spacing: -0.045em;
  line-height: 0.98;
}

.token-reference__intro span {
  display: block;
  max-width: 680px;
  color: var(--cadence-color-text-secondary);
  font-size: 15px;
  line-height: 1.6;
}

.token-reference section {
  padding: 36px 0 52px;
  border-top: 1px solid var(--cadence-color-border);
}

.token-reference__heading {
  display: grid;
  grid-template-columns: 44px 1fr;
  gap: 16px;
  margin-bottom: 28px;
}

.token-reference__heading > span {
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 11px;
}

.token-reference__heading h2 {
  margin: 5px 0 0;
  color: var(--cadence-color-text);
  font-size: 22px;
  font-weight: 560;
}

.color-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
  gap: 1px;
  overflow: hidden;
  border: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-border);
}

.color-grid article {
  min-width: 0;
  background: var(--cadence-color-surface);
}

.color-grid__swatch {
  height: 92px;
  border-bottom: 1px solid var(--cadence-color-border);
}

.color-grid code,
.type-grid code {
  display: block;
  overflow: hidden;
  padding: 13px 14px;
  color: var(--cadence-color-text-secondary);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.type-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

.type-grid article {
  min-width: 0;
  padding: 24px;
  border: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-surface);
}

.type-grid code {
  padding: 0 0 22px;
}

.type-grid p {
  margin: 0;
  color: var(--cadence-color-text-strong);
}

.type-grid__sans {
  font-family: var(--cadence-font-sans);
  font-size: clamp(24px, 3vw, 38px);
  letter-spacing: -0.03em;
  line-height: 1.08;
}

.type-grid__mono {
  font-family: var(--cadence-font-mono);
  font-size: clamp(16px, 2vw, 23px);
  line-height: 1.5;
}

.space-list {
  display: grid;
  gap: 1px;
  border: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-border);
}

.space-list article {
  display: grid;
  grid-template-columns: minmax(180px, 0.35fr) 1fr;
  align-items: center;
  gap: 20px;
  min-height: 54px;
  padding: 0 18px;
  background: var(--cadence-color-surface);
}

.space-list code {
  color: var(--cadence-color-text-secondary);
}

.space-list div {
  height: 10px;
  min-width: 4px;
  background: var(--cadence-color-accent);
}

@media (width <= 700px) {
  .type-grid {
    grid-template-columns: 1fr;
  }

  .space-list article {
    grid-template-columns: 1fr;
    gap: 8px;
    padding: 14px;
  }
}
</style>
