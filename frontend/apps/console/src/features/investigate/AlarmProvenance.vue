<script setup lang="ts">
import type { RouteLocationRaw } from "vue-router";
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { formatClock } from "@/ui";
import type { EpisodeDetail } from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { MONITORING_EDITS_PENDING } from "@/features/telemetry/index.ts";
import { sampleLink } from "./sample/link.ts";

/**
 * B1's provenance line (ux U71 A7): which limit raised the alarm and the sample that raised it
 * (Telemetry, centred and ringed). A ground limit says where it will be edited (#669: no limits
 * app to link to until #451). Ids go to Technical details.
 */
const props = defineProps<{ episode: EpisodeDetail; sc: FleetSpacecraft }>();
const e = computed(() => props.episode);
const version = computed(() => e.value.limit_definition_version ?? null);
const from = computed(() => {
  if (e.value.source === "catalog_monitoring") return "From the catalog's limits";
  if (version.value === null) return null;
  const set = e.value.limit_set_name ? ` in limit set ${e.value.limit_set_name}` : "";
  return `From ground limit v${version.value}${set}`;
});
const groundLimit = computed(() => e.value.source === "ground_limit" && from.value !== null);
const trigger = computed(() => e.value.trigger ?? null);
const sampleTo = computed<RouteLocationRaw | null>(() => {
  const t = trigger.value;
  return t?.sample_id ? sampleLink(props.sc.scid, t.point_id, { ...t, id: t.sample_id }) : null;
});
const ids = computed(() =>
  [
    e.value.limit_definition_id ? `Limit definition ${e.value.limit_definition_id}` : null,
    trigger.value?.sample_id ? `Sample ${trigger.value.sample_id}` : null,
  ].filter((x): x is string => x !== null),
);
</script>

<template>
  <div v-if="from || sampleTo" class="flex flex-col gap-1">
    <p class="m-0 flex flex-wrap gap-x-2 text-sm text-text-3">
      <span v-if="from">{{ from }}</span>
      <RouterLink v-if="sampleTo && trigger" :to="sampleTo" class="text-readout hover:underline"
        >Show the sample that raised it ({{ formatClock(new Date(trigger.at)) }}Z)</RouterLink
      >
    </p>
    <p v-if="groundLimit" class="m-0 text-sm text-text-3">{{ MONITORING_EDITS_PENDING }}</p>
    <details v-if="ids.length" class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p v-for="line in ids" :key="line" class="m-0 pt-1 font-mono break-all">{{ line }}</p>
    </details>
  </div>
</template>
