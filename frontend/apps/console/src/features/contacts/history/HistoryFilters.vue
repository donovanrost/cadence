<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApSelect, type ApSelectOption } from "@/ui";
import type { HistoryQuery } from "./history.ts";
import HistoryStateFilter from "./HistoryStateFilter.vue";
import { filterLine, type HistoryNames, type RowCounts } from "./words.ts";

/**
 * U78 filters: Spacecraft and Station selects and the State multi-select, with the filter line
 * '212 passes · Canceled · EARENDIL-312 · Fairbanks' and Clear filters while any is set.
 */
const props = defineProps<{
  query: HistoryQuery;
  spacecraft: readonly ApSelectOption<string>[];
  stations: readonly ApSelectOption<string>[];
  names: HistoryNames;
  /** Rows shown, or null while the week loads (the line waits rather than say 0). */
  counts: RowCounts | null;
  short: boolean;
}>();
const emit = defineEmits<{ filter: [patch: Record<string, string | undefined>] }>();
const ALL = "all";
const withAll = (label: string, options: readonly ApSelectOption<string>[]) => [
  { value: ALL, label },
  ...options,
];
const pick = (key: string, value: string) =>
  emit("filter", { [key]: value === ALL || value === "" ? undefined : value });
const filtered = computed(
  () =>
    props.query.spacecraftId !== null ||
    props.query.station !== null ||
    props.query.states.length > 0,
);
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex flex-wrap items-end gap-3">
      <div class="w-[200px]">
        <ApSelect
          :model-value="query.spacecraftId ?? ALL"
          label="Spacecraft"
          size="compact"
          :options="withAll('All spacecraft', spacecraft)"
          @update:model-value="(v) => pick('spacecraft', v)"
        />
      </div>
      <div class="w-[200px]">
        <ApSelect
          :model-value="query.station ?? ALL"
          label="Station"
          size="compact"
          :options="withAll('All stations', stations)"
          @update:model-value="(v) => pick('station', v)"
        />
      </div>
      <HistoryStateFilter :chosen="query.states" @state="(k) => emit('filter', { state: k })" />
    </div>
    <div v-if="filtered" class="flex flex-wrap items-center gap-3 text-sm text-text-3">
      <span v-if="counts">{{ filterLine(counts, short, names) }}</span>
      <ApButton
        size="compact"
        variant="ghost"
        @click="emit('filter', { spacecraft: undefined, station: undefined, state: undefined })"
        >Clear filters</ApButton
      >
    </div>
  </div>
</template>
