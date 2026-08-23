<script setup lang="ts">
import { CStatus } from "@cadence/ui";
</script>

<template>
  <main>
    <p>CADENCE / FEDERATED APPLICATION FIXTURE</p>
    <h1>Contract Probe</h1>
    <CStatus class="status" tone="nominal" pulse>Remote entry available</CStatus>
    <p class="hint">Mount this fixture from the Cadence host at 127.0.0.1:5173.</p>
  </main>
</template>

<style>
body {
  display: grid;
  place-items: center;
}

main {
  width: min(540px, calc(100vw - 48px));
  padding: 40px;
  border: 1px solid var(--cadence-color-border);
  background: var(--cadence-color-surface-inset);
}

main > p:first-child {
  color: var(--cadence-color-signal);
  font-family: var(--cadence-font-mono);
  font-size: 10px;
  letter-spacing: 0.12em;
}

h1 {
  margin: 8px 0 30px;
  font-size: 42px;
  letter-spacing: -0.04em;
}

.status {
  display: flex;
  padding: 14px;
  border: 1px solid #274743;
  background: #12201f;
}

.hint {
  margin: 24px 0 0;
  color: var(--cadence-color-text-muted);
  font-family: var(--cadence-font-mono);
  font-size: 11px;
}
</style>
