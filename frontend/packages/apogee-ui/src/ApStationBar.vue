<script setup lang="ts">
import { computed } from "vue";
import { stationItems } from "./command/stations.ts";

/** Inline station progress for takeover headers (CommandFlow). See command/stations.ts. */
const props = defineProps<{
  steps: readonly string[];
  /** Index (or indices) of the station(s) in progress. */
  current: number | readonly number[];
  label: string;
  collapseDoneBefore?: number | undefined;
  collapseFutureFrom?: number | undefined;
}>();
const items = computed(() =>
  stationItems(props.steps, typeof props.current === "number" ? [props.current] : props.current, {
    collapseDoneBefore: props.collapseDoneBefore,
    collapseFutureFrom: props.collapseFutureFrom,
  }),
);
</script>

<template>
  <ol :aria-label="label" class="m-0 flex list-none flex-wrap p-0">
    <li
      v-for="item in items"
      :key="item.key"
      :aria-current="item.state === 'current' ? 'step' : undefined"
      class="flex h-[52px] items-center gap-2 border-r border-hairline px-3.5 font-display text-md font-semibold tracking-tag uppercase"
      :class="{
        'bg-raised text-readout shadow-[inset_0_-2px_0_var(--color-readout)]':
          item.state === 'current',
        'text-text-4': item.state === 'done' || (item.state === 'future' && !item.collapsed),
        'text-line-strong': item.state === 'future' && item.collapsed,
      }"
    >
      <span
        v-if="!(item.state === 'future' && item.collapsed)"
        aria-hidden="true"
        class="font-mono"
        :class="item.state === 'done' ? 'text-nominal' : ''"
        >{{ item.state === "done" ? "✓" : item.state === "current" ? "●" : "○" }}</span
      >
      <span aria-hidden="true">{{ item.text }}</span>
      <span class="sr-only">{{ item.label }}</span>
    </li>
  </ol>
</template>
