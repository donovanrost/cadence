<script setup lang="ts">
import { CStatus } from "@cadence/ui";
import { manifest } from "./federated-application";
</script>

<template>
  <main class="remote-card">
    <p class="kicker">CADENCE / FIRST-PARTY FEDERATED APPLICATION</p>
    <h1>{{ manifest.application.displayName }}</h1>
    <CStatus class="status" tone="nominal" pulse>Remote entry available</CStatus>
    <p class="description">{{ manifest.application.description }}</p>
    <ul class="surface-list" aria-label="Contributed surfaces">
      <li v-for="surface in manifest.surfaces" :key="surface.surfaceId">
        <span>{{ surface.surfaceId.replaceAll("_", " ") }}</span>
        <code>{{ surface.dataContract.id }}</code>
      </li>
    </ul>
  </main>
</template>

<style>
:root {
  color-scheme: dark;
}

body {
  display: grid;
  min-height: 100vh;
  place-items: center;
  margin: 0;
  background: #0e1517;
  color: #dbe9e6;
  font-family: var(--cadence-font-sans, ui-sans-serif, sans-serif);
}

.remote-card {
  width: min(720px, calc(100vw - 48px));
  padding: 44px;
  border: 1px solid #274743;
  background: linear-gradient(145deg, #142122, #0f191a 60%, #12201f);
  box-shadow: 18px 18px 0 #081011;
}

.kicker,
code {
  color: #72d5c2;
  font-family: var(--cadence-font-mono, ui-monospace, monospace);
  font-size: 0.7rem;
  letter-spacing: 0.11em;
  text-transform: uppercase;
}

h1 {
  margin: 12px 0 24px;
  font-size: clamp(2.5rem, 7vw, 4.5rem);
  letter-spacing: -0.055em;
}

.status {
  display: inline-flex;
  margin-bottom: 18px;
}

.description {
  max-width: 54ch;
  color: #9cb2ad;
  line-height: 1.6;
}

.surface-list {
  display: grid;
  gap: 8px;
  margin: 28px 0 0;
  padding: 0;
  list-style: none;
}

.surface-list li {
  display: flex;
  justify-content: space-between;
  gap: 18px;
  padding: 10px 0;
  border-top: 1px solid #274743;
  color: #dbe9e6;
}

.surface-list code {
  color: #7e9a94;
  font-size: 0.62rem;
  letter-spacing: 0.04em;
  text-transform: none;
}
</style>
