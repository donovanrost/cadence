<script setup lang="ts">
import { computed } from "vue";
import type { FleetState } from "@/features/fleet/index.ts";
import { VIEW, type Dot } from "./constellation.ts";

/** Spacecraft dots by state; front-side criticals get a diamond ring and up to 3 name labels. */
const props = defineProps<{ dots: readonly Dot[]; dimmed?: boolean }>();

const FILL: Readonly<Record<FleetState, string>> = {
  critical: "fill-crit",
  caution: "fill-caution",
  stale: "fill-stale",
  nominal: "fill-nominal",
  never_heard: "fill-text-4",
};

const critical = computed(() =>
  props.dimmed ? [] : props.dots.filter((dot) => dot.state === "critical"),
);
const diamond = (dot: Dot) =>
  `M${dot.x} ${dot.y - 9}L${dot.x + 9} ${dot.y}L${dot.x} ${dot.y + 9}L${dot.x - 9} ${dot.y}Z`;
</script>

<template>
  <g :class="dimmed ? 'opacity-40' : ''">
    <circle
      v-for="dot in dots"
      :key="dot.id"
      :data-sc="dot.id"
      :cx="dot.x"
      :cy="dot.y"
      :r="dimmed ? dot.r * 0.8 : dot.r"
      class="cursor-pointer"
      :class="FILL[dot.state]"
    />
    <path
      v-for="dot in critical"
      :key="`r${dot.id}`"
      :d="diamond(dot)"
      fill="none"
      class="pointer-events-none stroke-crit"
    />
    <text
      v-for="dot in critical.slice(0, 3)"
      :key="`l${dot.id}`"
      :x="dot.x + (dot.x > VIEW.cx ? 14 : -14)"
      :y="dot.y - 12"
      :text-anchor="dot.x > VIEW.cx ? 'start' : 'end'"
      class="pointer-events-none fill-crit-text font-mono text-[11px]"
    >
      {{ dot.name }}
    </text>
  </g>
</template>
