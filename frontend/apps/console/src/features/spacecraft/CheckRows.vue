<script setup lang="ts">
import { ApTag, type OpState } from "@/ui";

/** Check rows (`poll` on the boards): label · sentence · verdict tag, problem rows washed. */
export type CheckRow = Readonly<{
  key: string;
  label: string;
  sentence: string;
  detail?: string | undefined;
  state: OpState;
  verdict: string;
}>;
defineProps<{ rows: readonly CheckRow[] }>();
</script>

<template>
  <ul class="m-0 list-none p-0">
    <li
      v-for="row in rows"
      :key="row.key"
      class="grid grid-cols-[110px_minmax(0,1fr)_auto] items-center gap-3 border-t border-hairline px-4 py-2.5 first:border-t-0"
      :class="{
        'bg-[var(--apogee-wash-caution)]': row.state === 'caution',
        'bg-[var(--apogee-wash-crit)]': row.state === 'crit',
      }"
    >
      <span class="ap-label">{{ row.label }}</span>
      <span class="flex flex-col gap-0.5">
        <span class="text-md text-readout">{{ row.sentence }}</span>
        <span v-if="row.detail" class="text-sm text-text-3">{{ row.detail }}</span>
      </span>
      <ApTag :state="row.state" :label="row.verdict" />
    </li>
  </ul>
</template>
