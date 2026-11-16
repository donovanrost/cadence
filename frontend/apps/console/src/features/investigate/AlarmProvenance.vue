<script setup lang="ts">
import type { RouteLocationRaw } from "vue-router";
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { formatClock } from "@/ui";
import type { EpisodeDetail } from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { sampleQuery } from "./sample/link.ts";

/**
 * B1's provenance line (ux U71 A7): which limit raised the alarm, a link to that limit version in
 * the limits app, and the sample that raised it (Telemetry, centred and ringed). Ids go to
 * Technical details.
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
const limitTo = computed<RouteLocationRaw | null>(() =>
  e.value.source === "ground_limit" && e.value.limit_definition_id && version.value !== null
    ? {
        name: "setup.app",
        params: { appKey: "limits", surface: "manage" },
        query: { definition: e.value.limit_definition_id, version: String(version.value) },
      }
    : null,
);
const trigger = computed(() => e.value.trigger ?? null);
const sampleTo = computed<RouteLocationRaw | null>(() =>
  trigger.value?.sample_id
    ? {
        name: "ops.spacecraft",
        params: { scId: props.sc.scid, tab: "telemetry" },
        query: {
          points: trigger.value.point_id,
          focus: trigger.value.point_id,
          at: trigger.value.at,
          ...sampleQuery(trigger.value.sample_id, trigger.value.receipt_time),
        },
      }
    : null,
);
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
      <RouterLink v-if="limitTo" :to="limitTo" class="text-readout hover:underline"
        >View limit v{{ version }}</RouterLink
      >
      <RouterLink v-if="sampleTo && trigger" :to="sampleTo" class="text-readout hover:underline"
        >Show the sample that raised it ({{ formatClock(new Date(trigger.at)) }}Z)</RouterLink
      >
    </p>
    <details v-if="ids.length" class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p v-for="line in ids" :key="line" class="m-0 pt-1 font-mono break-all">{{ line }}</p>
    </details>
  </div>
</template>
