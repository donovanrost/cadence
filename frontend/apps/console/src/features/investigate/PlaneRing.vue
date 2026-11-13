<script setup lang="ts">
import { computed } from "vue";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { ringDots, type RingTone } from "./sisters.ts";

/**
 * B4 mini plane ring (Investigate.md §B4): the plane's spacecraft around a ring by phase (else by
 * slot), the selected one crit and labelled, sisters in their state, the rest faint.
 */
const props = defineProps<{
  fleet: readonly FleetSpacecraft[];
  sc: FleetSpacecraft;
  sisters: ReadonlyMap<string, "crit" | "caution">;
}>();
const dots = computed(() => ringDots(props.fleet, props.sc, props.sisters));
const self = computed(() => dots.value.find((d) => d.tone === "self") ?? null);
const FILL: Readonly<Record<RingTone, string>> = {
  self: "fill-crit",
  crit: "fill-crit",
  caution: "fill-caution",
  other: "fill-text-4",
};
</script>

<template>
  <svg
    viewBox="0 0 100 100"
    class="size-[120px] flex-none overflow-visible"
    role="img"
    :aria-label="`${sc.name} and ${sisters.size} of ${dots.length - 1} plane sisters with this point out of limits`"
  >
    <circle cx="50" cy="50" r="40" fill="none" class="stroke-hairline" stroke-width="1" />
    <circle
      v-for="d in dots"
      :key="d.id"
      :cx="d.x"
      :cy="d.y"
      :r="d.tone === 'self' ? 4 : d.tone === 'other' ? 1.8 : 3"
      :class="FILL[d.tone]"
    />
    <circle
      v-if="self"
      :cx="self.x"
      :cy="self.y"
      r="7"
      fill="none"
      class="stroke-crit"
      stroke-width="1"
    />
    <text
      v-if="self"
      :x="self.x"
      :y="self.y > 50 ? self.y + 16 : self.y - 10"
      text-anchor="middle"
      class="fill-readout font-mono text-[9px]"
    >
      {{ sc.name }}
    </text>
  </svg>
</template>
