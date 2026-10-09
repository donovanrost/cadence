<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import { dashboardPath, type StudyDashboard } from "./fixtures";
import { ago } from "./state";

defineProps<{ dashboard: StudyDashboard }>();
</script>

<!-- A hero navigation card: reopens the dashboard exactly as it was last viewed. -->
<template>
  <article class="hud-corners flex flex-col border border-primary/40 bg-base-200 p-4">
    <p class="hud-label">Continue where you left off</p>
    <h2 class="mt-2 truncate text-lg font-semibold">{{ dashboard.name }}</h2>
    <p class="text-xs text-base-content/60">Viewed {{ ago(dashboard.lastViewedAt ?? 0) }}</p>
    <dl
      v-if="dashboard.lastContext"
      class="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-sm text-base-content/70"
    >
      <div class="flex items-center gap-1.5">
        <dt><CadenceIcon name="hero-clock" label="Time range" /></dt>
        <dd>{{ dashboard.lastContext.range }}</dd>
      </div>
      <div class="flex items-center gap-1.5">
        <dt><CadenceIcon name="hero-rocket-launch" label="Spacecraft" /></dt>
        <dd class="font-mono">{{ dashboard.lastContext.scope }}</dd>
      </div>
    </dl>
    <div class="mt-auto flex flex-wrap items-center gap-2 pt-4">
      <!-- CadenceButton has no link form; these are the button recipes on anchors. -->
      <a
        :href="dashboardPath(dashboard.id) + (dashboard.lastContext?.query ?? '')"
        class="btn btn-primary btn-sm gap-1"
      >
        <CadenceIcon name="hero-play" />Resume
      </a>
      <a
        v-if="dashboard.lastContext"
        :href="dashboardPath(dashboard.id)"
        class="btn btn-ghost btn-sm"
        >Open with defaults</a
      >
    </div>
  </article>
</template>
