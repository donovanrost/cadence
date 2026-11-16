<script setup lang="ts">
import { computed } from "vue";
import type { WorkspacePlacement } from "../model/snapshot.ts";
import { formatTime, limitLabel, stateLanes, type LimitState } from "../model/widget-data.ts";

/**
 * State lanes. Limit-carrying segments use the state fills (with the word in the segment and
 * its title); plain enum states use neutral steps only (no hues, OpsLists rule).
 */
const props = defineProps<{ placement: WorkspacePlacement; now: number }>();
const lanes = computed(() => stateLanes(props.placement, props.now));
const span = computed(() => {
  const segments = lanes.value.flatMap((lane) => lane.segments);
  const from = Math.min(...segments.map((s) => s.from));
  const to = Math.max(...segments.map((s) => s.to));
  return { from, width: Math.max(to - from, 1) };
});
const fill: Readonly<Record<LimitState, string>> = {
  red: "bg-crit text-on-action",
  yellow: "bg-caution text-on-action",
  blue: "bg-raised-hi text-readout",
  green: "bg-nominal-dim text-readout",
};
const neutral = ["bg-raised text-text-2", "bg-raised-hi text-text-2", "bg-cell-empty text-text-3"];
function tone(state: string, limit: LimitState | null): string {
  if (limit) return fill[limit];
  let hash = 0;
  for (const char of state) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return neutral[hash % neutral.length] ?? "bg-raised text-text-2";
}
const offset = (value: number) => `${((value - span.value.from) / span.value.width) * 100}%`;
const width = (from: number, to: number) =>
  `${Math.max(((to - from) / span.value.width) * 100, 0.4)}%`;
const title = (state: string, limit: LimitState | null, from: number) =>
  `${state}${limit ? ` (${limitLabel[limit]})` : ""} · ${formatTime(from)}`;
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-2 overflow-auto px-3 py-2">
    <div v-for="lane in lanes" :key="lane.key" class="space-y-1">
      <p class="truncate font-display text-xs uppercase tracking-tag text-text-3">
        {{ lane.label }}
      </p>
      <div class="relative h-6 overflow-hidden border border-hairline-faint bg-vacuum">
        <div
          v-for="segment in lane.segments"
          :key="segment.key"
          class="absolute inset-y-0 flex items-center overflow-hidden border-r border-vacuum px-1 font-mono text-2xs"
          :class="tone(segment.state, segment.limit)"
          :style="{ left: offset(segment.from), width: width(segment.from, segment.to) }"
          :title="title(segment.state, segment.limit, segment.from)"
        >
          <span class="truncate">{{ segment.state }}</span>
          <!-- The limit is colour and hover title otherwise (a11y B2). -->
          <span v-if="segment.limit" class="sr-only">, {{ limitLabel[segment.limit] }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
