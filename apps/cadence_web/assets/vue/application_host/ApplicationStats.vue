<script setup lang="ts">
import StatusBadge from "../StatusBadge.vue"
import type {Stat} from "./presentation_types"

defineProps<{stats: Stat[]}>()
</script>

<template>
  <section
    id="application-surface-stats"
    class="grid gap-4 md:grid-cols-3"
  >
    <section
      v-for="stat in stats"
      :id="stat.id"
      :key="stat.stat_id"
      class="card border border-base-300 bg-base-200"
    >
      <div class="card-body p-6">
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="hud-label">{{ stat.label }}</p>
            <p class="mt-2 text-2xl font-semibold">{{ stat.value }}</p>
          </div>
          <StatusBadge :status="stat.tone" :label="stat.tone_label" />
        </div>
      </div>
    </section>
  </section>
</template>
