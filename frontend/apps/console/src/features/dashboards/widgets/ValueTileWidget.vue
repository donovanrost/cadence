<script setup lang="ts">
import { computed } from "vue";
import { ApStatusMark, stateTextClass } from "@/ui";
import type { ReadyPlacement } from "../model/snapshot.ts";
import {
  formatTime,
  limitLabel,
  limitMark,
  valueTile,
  worstLimitState,
} from "../model/widget-data.ts";

/** One live value. A limit state shows as mark + word next to the value, never color alone. */
const props = defineProps<{ placement: ReadyPlacement }>();
const data = computed(() => valueTile(props.placement));
const limit = computed(() => worstLimitState(props.placement));
const mark = computed(() => (limit.value ? limitMark[limit.value] : null));
const showUnit = computed(() => props.placement.widget.options.show_unit !== false);
const outOfLimits = computed(() => mark.value === "crit" || mark.value === "caution");
</script>

<template>
  <div class="flex h-full min-h-0 flex-col items-center justify-center gap-1 px-3 text-center">
    <template v-if="data.kind === 'value'">
      <p class="flex items-baseline gap-2 font-sans tabular-nums leading-none">
        <span
          class="text-[clamp(1.5rem,4vw,3rem)] tracking-tight"
          :class="mark && outOfLimits ? stateTextClass(mark) : 'text-readout'"
          :data-workspace-value="placement.id"
          >{{ data.text }}</span
        >
        <span v-if="data.unit && showUnit" class="text-sm text-text-3">{{ data.unit }}</span>
      </p>
      <p
        v-if="limit && mark"
        class="flex items-center gap-1.5 font-display text-xs uppercase tracking-tag"
        :class="stateTextClass(mark)"
      >
        <ApStatusMark :state="mark" />{{ limitLabel[limit] }}
      </p>
      <p v-if="data.at !== null" class="font-mono text-xs text-text-4">{{ formatTime(data.at) }}</p>
    </template>
    <p v-else-if="data.kind === 'ambiguous'" class="text-sm text-text-3">
      This tile resolves more than one value. Bind it to a single point.
    </p>
    <p v-else class="text-sm text-text-3">No data in this range.</p>
  </div>
</template>
