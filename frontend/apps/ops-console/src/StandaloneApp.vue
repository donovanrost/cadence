<script setup lang="ts">
import { CStatus } from "@cadence/ui";
</script>

<template>
  <main class="ops-standalone">
    <p class="ops-kicker">CADENCE / FEDERATED APPLICATION</p>
    <h1>Ops Console</h1>
    <CStatus class="ops-status" tone="nominal" pulse>Remote entry available</CStatus>
    <p class="ops-hint">Mount this mission-scoped operations surface from the Phoenix host.</p>
  </main>
</template>

<style>
:root {
  color-scheme: dark;
  background: #0d1214;
  color: #d6e0df;
  font-family: "Archivo Variable", ui-sans-serif, sans-serif;
}

body {
  display: grid;
  min-height: 100vh;
  margin: 0;
  place-items: center;
  background:
    linear-gradient(rgba(27, 52, 52, 0.18) 1px, transparent 1px),
    linear-gradient(90deg, rgba(27, 52, 52, 0.18) 1px, transparent 1px),
    #0d1214;
  background-size: 32px 32px;
}

.ops-standalone {
  width: min(560px, calc(100vw - 48px));
  padding: 42px;
  border: 1px solid #284647;
  background: rgba(17, 28, 30, 0.94);
  box-shadow: 18px 18px 0 rgba(11, 19, 20, 0.7);
}

.ops-kicker {
  margin: 0;
  color: #65d5c4;
  font-family: "JetBrains Mono Variable", ui-monospace, monospace;
  font-size: 10px;
  letter-spacing: 0.16em;
}

h1 {
  margin: 10px 0 30px;
  font-size: 44px;
  letter-spacing: -0.05em;
}

.ops-status {
  display: flex;
  padding: 14px;
  border: 1px solid #2e5d57;
  background: #122622;
  font-family: "JetBrains Mono Variable", ui-monospace, monospace;
  font-size: 12px;
  text-transform: uppercase;
}

.ops-hint {
  margin: 24px 0 0;
  color: #8ca09e;
  font-family: "JetBrains Mono Variable", ui-monospace, monospace;
  font-size: 11px;
}
</style>
