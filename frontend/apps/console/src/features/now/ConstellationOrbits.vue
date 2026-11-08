<script setup lang="ts">
import type { Orbit } from "./constellation.ts";

/** One half of every orbit ellipse (back half drawn before the Earth disc, front half after). */
defineProps<{ orbits: readonly Orbit[]; half: "back" | "front"; selectedPlane: number | null }>();
const emit = defineEmits<{ selectPlane: [plane: number | null] }>();
</script>

<template>
  <g fill="none" stroke-width="1">
    <path
      v-for="orbit in orbits"
      :key="orbit.plane"
      :d="half === 'back' ? orbit.back : orbit.front"
      :class="[
        half === 'back'
          ? orbit.plane === selectedPlane
            ? 'stroke-readout/50'
            : 'stroke-viz-orbit/60'
          : orbit.plane === selectedPlane
            ? 'cursor-pointer stroke-readout'
            : 'cursor-pointer stroke-viz-orbit',
      ]"
      @click.stop="
        half === 'front' && emit('selectPlane', orbit.plane === selectedPlane ? null : orbit.plane)
      "
    />
  </g>
</template>
