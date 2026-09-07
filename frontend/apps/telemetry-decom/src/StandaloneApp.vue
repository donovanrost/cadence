<script setup lang="ts">
import { CadenceCard, CadenceStatus } from "@cadence/ui";
import { manifest } from "./federated-application";
</script>
<template>
  <main class="mx-auto max-w-3xl p-6">
    <CadenceCard>
      <p class="hud-label">Cadence application</p>
      <h1 class="text-2xl font-semibold">{{ manifest.application.displayName }}</h1>
      <p class="text-sm text-muted">{{ manifest.application.description }}</p>
      <CadenceStatus tone="nominal">Remote entry available</CadenceStatus>
      <ul class="mt-4 space-y-2" aria-label="Contributed surfaces">
        <li
          v-for="surface in manifest.surfaces"
          :key="surface.surfaceId"
          class="flex flex-wrap justify-between gap-2 border-t border-primary/20 pt-2 text-sm"
        >
          <span>{{ surface.surfaceId.replaceAll("_", " ") }}</span>
          <code class="text-xs text-muted">{{ surface.dataContract.id }}</code>
        </li>
      </ul>
    </CadenceCard>
  </main>
</template>
