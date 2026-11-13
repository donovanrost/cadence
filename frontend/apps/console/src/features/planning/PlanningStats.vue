<script setup lang="ts">
import { ApStatTile } from "@/ui";
import type { PlanningSummary } from "./api.ts";

/** P1 coverage tiles: spacecraft covered, templates, contacts and uplink passes a day. */
defineProps<{ summary: PlanningSummary }>();
</script>

<template>
  <div class="grid grid-cols-2 gap-px border border-hairline bg-hairline md:grid-cols-4">
    <ApStatTile
      label="Spacecraft covered"
      :value="summary.coverage.covered"
      :denominator="summary.coverage.spacecraft_total"
      :state="summary.coverage.covered < summary.coverage.spacecraft_total ? 'caution' : 'neutral'"
    />
    <ApStatTile label="Templates" :value="summary.templates.length" />
    <ApStatTile
      label="Contacts per day"
      :value="summary.coverage.contacts_per_day"
      :caption="summary.coverage.contacts_per_day === null ? 'not computed yet' : undefined"
    />
    <ApStatTile
      label="Uplink passes per day"
      :value="summary.coverage.uplink_passes_per_day"
      :caption="summary.coverage.uplink_passes_per_day === null ? 'not computed yet' : undefined"
    />
  </div>
</template>
