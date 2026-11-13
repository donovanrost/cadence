<script setup lang="ts">
import { computed } from "vue";
import { ApStatStrip, ApStatTile } from "@/ui";
import type { ReviewSummary } from "./api.ts";
import { bytes, minutes, ownerCaption } from "./format.ts";

/**
 * Stat strip: Planned · Realized · Partial · Missed (failed folds in) · Downlink · Minutes flown.
 * Downlink is received vs provider-reported; there's no planned volume, and unknown isn't 0.
 */
const props = defineProps<{ summary: ReviewSummary }>();
const counted = computed(() => props.summary.planned - props.summary.canceled);
const flown = computed(() => props.summary.by_station.reduce((n, s) => n + s.flown_seconds, 0));
const volume = computed(() => props.summary.volume ?? null);
const planned = computed(() => props.summary.by_station.reduce((n, s) => n + s.planned_seconds, 0));
const plannedCaption = computed(() =>
  props.summary.canceled > 0 ? `${props.summary.canceled} canceled by us, not counted` : undefined,
);
/** Downlink tile: received vs provider-reported; unknown is said, never 0. */
const volumeTile = computed(() => {
  const v = volume.value;
  if (!v) return { value: null, caption: undefined, state: undefined };
  return {
    value: v.received_bytes === null ? "Not known" : bytes(v.received_bytes),
    caption:
      v.provider_bytes === null
        ? "No provider reports"
        : `provider reported ${bytes(v.provider_bytes)}`,
    state:
      v.received_bytes !== null && v.provider_bytes !== null && v.received_bytes < v.provider_bytes
        ? ("caution" as const)
        : undefined,
  };
});
</script>

<template>
  <ApStatStrip :columns="volume ? 6 : 5" label="Pass review totals">
    <ApStatTile label="Planned" :value="summary.planned" :caption="plannedCaption" />
    <ApStatTile
      label="Realized"
      :value="summary.realized"
      :denominator="counted"
      state="nominal"
      :share="counted > 0 ? summary.realized / counted : undefined"
    />
    <ApStatTile
      label="Partial"
      :value="summary.partial"
      :state="summary.partial > 0 ? 'caution' : undefined"
      :caption="ownerCaption(summary.partial_by_owner)"
    />
    <ApStatTile
      label="Missed"
      :value="summary.missed + summary.failed"
      :state="summary.missed + summary.failed > 0 ? 'crit' : undefined"
      :caption="ownerCaption(summary.missed_by_owner)"
    />
    <ApStatTile
      v-if="volume"
      label="Downlink received"
      :value="volumeTile.value"
      :caption="volumeTile.caption"
      :state="volumeTile.state"
    />
    <ApStatTile
      label="Minutes flown"
      :value="minutes(flown)"
      :caption="`of ${minutes(planned)} planned`"
    />
  </ApStatStrip>
</template>
