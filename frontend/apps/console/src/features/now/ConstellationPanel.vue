<script setup lang="ts">
import { computed } from "vue";
import { plural, ApEmptyState, ApPanel } from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import ConstellationDots from "./ConstellationDots.vue";
import ConstellationOrbits from "./ConstellationOrbits.vue";
import { constellation, VIEW } from "./constellation.ts";

/** A1 · Constellation schematic (no ground-track mode: DECISIONS #4). */
const props = defineProps<{
  spacecraft: readonly FleetSpacecraft[];
  selectedPlane: number | null;
}>();
const emit = defineEmits<{ open: [id: string]; selectPlane: [plane: number | null] }>();

const drawing = computed(() => constellation(props.spacecraft));
const planeCount = computed(() => drawing.value?.orbits.length ?? 0);
const front = computed(() => drawing.value?.dots.filter((dot) => !dot.back) ?? []);
const behind = computed(() => drawing.value?.dots.filter((dot) => dot.back) ?? []);

const label = computed(() => {
  const crit = props.spacecraft.filter((sc) => sc.state === "critical").map((sc) => sc.name);
  return `Constellation schematic, ${plural(planeCount.value, "plane")}. ${
    crit.length ? `Critical: ${crit.slice(0, 5).join(", ")}.` : "None critical."
  }`;
});

function onClick(event: MouseEvent) {
  const el = event.target instanceof Element ? event.target.closest("[data-sc]") : null;
  const id = el?.getAttribute("data-sc");
  if (id) emit("open", id);
}
</script>

<template>
  <ApPanel
    index="A1"
    title="Constellation"
    :meta="drawing ? `${plural(planeCount, 'plane')} · schematic` : undefined"
    pane
    flush
  >
    <ApEmptyState
      v-if="!drawing"
      state="off"
      headline="Orbit data not available"
      sentence="The constellation view needs a plane and an in-plane phase for each spacecraft."
    />
    <svg
      v-else
      role="img"
      :aria-label="label"
      :viewBox="`0 0 ${VIEW.w} ${VIEW.h}`"
      class="h-full max-h-full w-full"
      preserveAspectRatio="xMidYMid meet"
      @click="onClick"
    >
      <ConstellationOrbits :orbits="drawing.orbits" half="back" :selected-plane="selectedPlane" />
      <ConstellationDots :dots="behind" dimmed />
      <circle
        :cx="VIEW.cx"
        :cy="VIEW.cy"
        :r="VIEW.earthR"
        class="fill-viz-earth stroke-viz-earth-line"
      />
      <ConstellationOrbits
        :orbits="drawing.orbits"
        half="front"
        :selected-plane="selectedPlane"
        @select-plane="emit('selectPlane', $event)"
      />
      <ConstellationDots :dots="front" />
    </svg>
  </ApPanel>
</template>
