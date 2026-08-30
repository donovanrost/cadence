<script setup lang="ts">
import type { StatusSymbolRole } from "./status-symbol";

withDefaults(
  defineProps<{
    label?: string;
    size?: 16 | 20 | 24;
    status: StatusSymbolRole;
  }>(),
  {
    label: undefined,
    size: 20,
  },
);
</script>

<template>
  <svg
    :class="['cui-status-symbol', `cui-status-symbol--${status}`]"
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    :role="label ? 'img' : undefined"
    :aria-label="label"
    :aria-hidden="label ? undefined : true"
    :data-status-role="status"
    focusable="false"
  >
    <path
      v-if="status === 'critical'"
      class="cui-status-symbol__filled"
      d="M2.5 3.5h19L12 21z"
      data-symbol-shape="downward-triangle"
    />
    <path
      v-else-if="status === 'serious'"
      class="cui-status-symbol__filled"
      d="M12 2.5 21.5 12 12 21.5 2.5 12z"
      data-symbol-shape="diamond"
    />
    <rect
      v-else-if="status === 'caution'"
      class="cui-status-symbol__filled"
      x="3.5"
      y="3.5"
      width="17"
      height="17"
      data-symbol-shape="square"
    />
    <circle
      v-else-if="status === 'normal'"
      class="cui-status-symbol__filled"
      cx="12"
      cy="12"
      r="8.5"
      data-symbol-shape="large-circle"
    />
    <circle
      v-else-if="status === 'standby'"
      class="cui-status-symbol__ring"
      cx="12"
      cy="12"
      r="7.5"
      data-symbol-shape="ring"
    />
    <circle
      v-else-if="status === 'off'"
      class="cui-status-symbol__filled"
      cx="12"
      cy="12"
      r="4.5"
      data-symbol-shape="small-circle"
    />
    <g v-else class="cui-status-symbol__unknown" data-symbol-shape="question-square">
      <rect x="3.5" y="3.5" width="17" height="17" />
      <path d="M9 9a3 3 0 1 1 3 3v2" />
      <path d="M12 17.25v.25" />
    </g>
  </svg>
</template>

<style scoped>
.cui-status-symbol {
  display: inline-block;
  flex: none;
  overflow: visible;
  color: var(--cadence-color-text-muted);
  shape-rendering: geometricprecision;
  vertical-align: middle;
}

.cui-status-symbol--critical {
  color: var(--cadence-color-status-critical, var(--cadence-color-danger));
}

.cui-status-symbol--serious {
  color: var(--cadence-color-status-serious, var(--cadence-color-warning));
}

.cui-status-symbol--caution {
  color: var(--cadence-color-status-caution, var(--cadence-color-warning));
}

.cui-status-symbol--normal {
  color: var(--cadence-color-status-normal, var(--cadence-color-success));
}

.cui-status-symbol--standby {
  color: var(--cadence-color-status-standby, var(--cadence-color-signal));
}

.cui-status-symbol--off {
  color: var(--cadence-color-status-off, var(--cadence-color-text-muted));
}

.cui-status-symbol--unknown {
  color: var(--cadence-color-status-unknown, var(--cadence-color-text-secondary));
}

.cui-status-symbol__filled {
  fill: currentcolor;
}

.cui-status-symbol__ring,
.cui-status-symbol__unknown {
  fill: none;
  stroke: currentcolor;
  stroke-width: 2.5;
  stroke-linecap: square;
  stroke-linejoin: miter;
  vector-effect: non-scaling-stroke;
}

.cui-status-symbol__unknown path:last-child {
  stroke-width: 3;
}
</style>
