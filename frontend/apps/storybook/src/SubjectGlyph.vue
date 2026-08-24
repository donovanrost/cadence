<script setup lang="ts">
import type { MonitoringSubjectKind } from "./monitoring-fixtures";

withDefaults(
  defineProps<{
    kind: MonitoringSubjectKind;
    size?: 24 | 32;
  }>(),
  {
    size: 24,
  },
);
</script>

<template>
  <svg
    class="subject-glyph"
    :width="size"
    :height="size"
    viewBox="0 0 32 32"
    aria-hidden="true"
    focusable="false"
    :data-subject-kind="kind"
  >
    <g v-if="kind === 'spacecraft'">
      <path d="M11 10h10v12H11z" />
      <path d="M3 12h6v8H3zM23 12h6v8h-6z" />
      <path d="M16 5v5M13 5h6M16 22v5M13 27h6" />
    </g>
    <g v-else-if="kind === 'ground-station'">
      <path d="M7 7c0 7.2 5.8 13 13 13" />
      <path d="m7 7 13 13M20 20l5-5" />
      <path d="M16 21v6M10 27h12" />
      <path d="M21 6c2.8 1 4.9 3.2 5.9 6" />
    </g>
    <g v-else-if="kind === 'telemetry-stream'">
      <path d="M3 16h5l3-8 5 16 4-12 3 4h6" />
      <path d="M3 6h26M3 26h26" class="subject-glyph__secondary" />
    </g>
    <g v-else>
      <path d="M3 16h20" />
      <path d="m18 10 6 6-6 6" />
      <path d="M5 10V6h22v20H5v-4" class="subject-glyph__secondary" />
    </g>
  </svg>
</template>

<style scoped>
.subject-glyph {
  display: block;
  color: var(--cadence-color-text-strong);
  fill: none;
  shape-rendering: geometricprecision;
  stroke: currentcolor;
  stroke-linecap: square;
  stroke-linejoin: miter;
  stroke-width: 1.5;
  vector-effect: non-scaling-stroke;
}

.subject-glyph__secondary {
  color: var(--cadence-color-text-muted);
}
</style>
