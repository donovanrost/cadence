<script setup lang="ts">
import { computed } from "vue";
import type { WorkspacePlacement } from "../../workspace/contracts";
import { formatTime, valueTile, worstLimitState, type LimitState } from "../widget-data";

const props = defineProps<{ placement: WorkspacePlacement }>();
const data = computed(() => valueTile(props.placement));
const state = computed(() => worstLimitState(props.placement));
const showUnit = computed(() => props.placement.widget?.options.show_unit !== false);
const valueTone: Record<LimitState, string> = {
  red: "text-error",
  yellow: "text-warning",
  blue: "text-info",
  green: "text-base-content",
};
</script>

<template>
  <div class="flex h-full min-h-0 flex-col items-center justify-center gap-1 px-3 text-center">
    <template v-if="data.kind === 'value'">
      <p class="flex items-baseline gap-2 font-mono tabular-nums leading-none">
        <span
          class="text-[clamp(1.5rem,4vw,3rem)] font-semibold"
          :class="state ? valueTone[state] : 'text-base-content'"
          :data-workspace-value="placement.id"
          >{{ data.text }}</span
        >
        <span v-if="data.unit && showUnit" class="text-sm text-base-content/70">{{
          data.unit
        }}</span>
      </p>
      <p v-if="data.at !== null" class="font-mono text-xs text-base-content/60">
        {{ formatTime(data.at) }}
      </p>
    </template>
    <p v-else-if="data.kind === 'ambiguous'" class="text-xs text-base-content/70">
      This value tile resolves more than one value. Bind it to a single observable.
    </p>
    <p v-else class="text-xs text-base-content/60">No data in this time range.</p>
  </div>
</template>
