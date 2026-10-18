<script setup lang="ts">
import { CadenceButton, CadenceCard, CadenceStatus, CadenceTextField } from "@cadence/ui";
import { ref } from "vue";
const name = ref("Artemis relay");
const colors = [
  "--surface-base",
  "--surface-inset",
  "--surface-raised",
  "--surface-elevated",
  "--color-action",
  "--text-bright",
  "--text-subtle",
  "--text-muted",
  "--status-success",
  "--status-warning",
  "--status-critical",
  "--status-info",
];
const spaces = ["--space-1", "--space-2", "--space-3", "--space-4", "--space-6", "--space-8"];
</script>
<template>
  <main class="mx-auto max-w-6xl space-y-8 p-6" id="production-foundations">
    <header class="border-b border-primary/20 pb-4">
      <p class="hud-label mb-2">Cadence design system</p>
      <h1 class="text-2xl font-semibold text-base-content">Production foundations</h1>
      <p class="mt-2 text-sm text-muted">
        The shared visual language used by Phoenix, Vue applications, and this workshop.
      </p>
    </header>
    <section aria-labelledby="colors-title">
      <h2 id="colors-title" class="hud-label mb-4">Semantic colors</h2>
      <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
        <article
          v-for="token in colors"
          :key="token"
          class="overflow-hidden rounded-sm border border-primary/20"
        >
          <div class="h-16" :style="{ background: `var(${token})` }"></div>
          <code class="block p-3 text-xs text-base-content">{{ token }}</code>
        </article>
      </div>
    </section>
    <div class="grid gap-6 md:grid-cols-2">
      <CadenceCard
        ><h2 class="hud-label">Typography</h2>
        <p class="text-xl">Mission operations</p>
        <p class="text-sm">Interface text follows the shared sans-serif stack.</p>
        <p class="font-mono text-sm">2026-09-05 18:42:07 UTC · 48.2 dB-Hz</p></CadenceCard
      >
      <CadenceCard
        ><h2 class="hud-label">Spacing</h2>
        <div v-for="space in spaces" :key="space" class="flex items-center gap-4">
          <code class="w-28 text-xs">{{ space }}</code
          ><span class="block h-3 bg-primary" :style="{ width: `var(${space})` }"></span></div
      ></CadenceCard>
    </div>
    <CadenceCard>
      <h2 class="hud-label">Controls and operational states</h2>
      <CadenceTextField
        id="foundation-name"
        v-model="name"
        label="Mission name"
        hint="A shared control with production styling."
      />
      <div class="flex flex-wrap gap-3">
        <CadenceButton variant="primary">Save changes</CadenceButton
        ><CadenceButton variant="outline">Cancel</CadenceButton
        ><CadenceButton variant="danger">Delete mission</CadenceButton
        ><CadenceButton loading>Saving</CadenceButton>
      </div>
      <div class="flex flex-wrap gap-3">
        <CadenceStatus tone="nominal">Nominal</CadenceStatus
        ><CadenceStatus tone="warning">Delayed telemetry</CadenceStatus
        ><CadenceStatus tone="danger">Failed</CadenceStatus><CadenceStatus>Unknown</CadenceStatus>
      </div>
    </CadenceCard>
  </main>
</template>
