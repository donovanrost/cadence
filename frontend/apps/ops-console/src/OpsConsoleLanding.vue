<script setup lang="ts">
defineProps<{
  missionId: string;
  missionName: string;
  componentCount: number;
}>();
</script>

<template>
  <section id="ops-console-surface" class="ops-console-surface">
    <p class="ops-console-eyebrow">MISSION OPERATIONS</p>
    <h1>{{ missionName }}</h1>
    <p class="ops-console-copy">
      Phoenix selected this Ops Console surface for mission <code>{{ missionId }}</code>.
    </p>
    <div class="ops-console-status" role="status">
      <span class="ops-console-status-dot" aria-hidden="true"></span>
      <span>Server authority connected · {{ componentCount }} domain components available</span>
    </div>
  </section>
</template>

<style scoped>
.ops-console-surface {
  min-height: 220px;
  padding: 32px;
  border: 1px solid var(--cadence-color-border, #284647);
  background: var(--cadence-color-surface-inset, #111c1e);
}

.ops-console-eyebrow {
  margin: 0;
  color: var(--cadence-color-accent, #65d5c4);
  font-family: var(--cadence-font-mono, ui-monospace, monospace);
  font-size: 10px;
  letter-spacing: 0.14em;
}

h1 {
  margin: 8px 0 12px;
  font-size: clamp(28px, 5vw, 48px);
  letter-spacing: -0.05em;
}

.ops-console-copy {
  max-width: 56ch;
  color: var(--cadence-color-text-muted, #8ca09e);
  font-size: 14px;
}

code {
  font-family: var(--cadence-font-mono, ui-monospace, monospace);
}

.ops-console-status {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  margin-top: 28px;
  padding: 9px 12px;
  border: 1px solid color-mix(in srgb, var(--cadence-color-signal, #65d5c4) 35%, transparent);
  color: var(--cadence-color-signal, #65d5c4);
  font-family: var(--cadence-font-mono, ui-monospace, monospace);
  font-size: 11px;
}

.ops-console-status-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--cadence-color-signal, #65d5c4);
  box-shadow: 0 0 0 4px color-mix(in srgb, var(--cadence-color-signal, #65d5c4) 12%, transparent);
}
</style>
