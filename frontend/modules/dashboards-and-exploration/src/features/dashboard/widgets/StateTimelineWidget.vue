<script setup lang="ts">
import { computed } from "vue";
import type { WorkspacePlacement } from "../../workspace/contracts";
import { formatTime, stateLanes, type LimitState } from "../widget-data";

const props = defineProps<{ placement: WorkspacePlacement; now: number }>();
const lanes = computed(() => stateLanes(props.placement, props.now));
const span = computed(() => {
  const segments = lanes.value.flatMap((lane) => lane.segments);
  const from = Math.min(...segments.map((s) => s.from));
  const to = Math.max(...segments.map((s) => s.to));
  return { from, width: Math.max(to - from, 1) };
});
const fill: Record<LimitState, string> = {
  red: "bg-error/70",
  yellow: "bg-warning/70",
  blue: "bg-info/60",
  green: "bg-success/50",
};
const neutral = ["bg-primary/40", "bg-secondary/40", "bg-accent/40", "bg-base-content/25"];
function tone(state: string, limit: LimitState | null) {
  if (limit) return fill[limit];
  let hash = 0;
  for (const char of state) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return neutral[hash % neutral.length];
}
const offset = (value: number) => `${((value - span.value.from) / span.value.width) * 100}%`;
const width = (from: number, to: number) =>
  `${Math.max(((to - from) / span.value.width) * 100, 0.4)}%`;
</script>

<template>
  <div class="flex h-full min-h-0 flex-col gap-2 overflow-auto px-3 py-2">
    <div v-for="lane in lanes" :key="lane.key" class="space-y-1">
      <p class="truncate text-xs text-base-content/70">{{ lane.label }}</p>
      <div class="relative h-6 overflow-hidden rounded-sm bg-base-300/40">
        <div
          v-for="segment in lane.segments"
          :key="segment.key"
          class="absolute inset-y-0 flex items-center overflow-hidden border-r border-base-100/60 px-1 font-mono text-[0.65rem]"
          :class="tone(segment.state, segment.limit)"
          :style="{ left: offset(segment.from), width: width(segment.from, segment.to) }"
          :title="`${segment.state} · ${formatTime(segment.from)}`"
        >
          <span class="truncate">{{ segment.state }}</span>
        </div>
      </div>
    </div>
  </div>
</template>
