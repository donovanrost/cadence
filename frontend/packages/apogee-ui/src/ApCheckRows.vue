<script setup lang="ts">
import ApTag from "./ApTag.vue";
import type { OpState } from "./status.ts";

/**
 * Check rows (`poll` on the boards): label · sentence (+ detail) · verdict tag, problem rows washed.
 * Used by readiness checks, change-set checks and commanding preflight. An optional `action` slot
 * renders one control per row (e.g. `Review` on a failed preflight check). `dimmed` shows rows from
 * an earlier check (U27): no problem washes and every verdict tag in the neutral off state, its word
 * kept at full contrast; the caller names the state in words ("From the previous check").
 */
export type ApCheckRow = Readonly<{
  key: string;
  label: string;
  sentence: string;
  detail?: string | undefined;
  state: OpState;
  verdict: string;
}>;
withDefaults(
  defineProps<{
    rows: readonly ApCheckRow[];
    labelWidth?: number | undefined;
    dimmed?: boolean | undefined;
  }>(),
  { labelWidth: 110, dimmed: false },
);
defineSlots<{ action?: (props: { row: ApCheckRow }) => unknown }>();
</script>

<template>
  <ul class="m-0 list-none p-0">
    <li
      v-for="row in rows"
      :key="row.key"
      class="grid items-center gap-3 border-t border-hairline px-4 py-2.5 first:border-t-0"
      :class="{
        'bg-[var(--apogee-wash-caution)]': !dimmed && row.state === 'caution',
        'bg-[var(--apogee-wash-crit)]': !dimmed && row.state === 'crit',
      }"
      :style="{
        gridTemplateColumns: `${labelWidth}px minmax(0, 1fr) auto${$slots.action ? ' auto' : ''}`,
      }"
    >
      <span class="ap-label">{{ row.label }}</span>
      <span class="flex flex-col gap-0.5">
        <span class="text-md text-readout">{{ row.sentence }}</span>
        <span v-if="row.detail" class="text-sm text-text-3">{{ row.detail }}</span>
      </span>
      <ApTag :state="dimmed ? 'off' : row.state" :label="row.verdict" />
      <span v-if="$slots.action"><slot name="action" :row="row" /></span>
    </li>
  </ul>
</template>
