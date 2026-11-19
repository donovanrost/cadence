<script setup lang="ts">
import { computed } from "vue";
import { ApPanel } from "@/ui";
import type { ReviewDaily } from "./api.ts";
import PercentTicks from "./PercentTicks.vue";
import { causeText, dayRatio, fillDays, percent } from "./format.ts";

/** R3 · Realization over 30 days: one bar per UTC day (height = realized %), dashed target. */
const props = defineProps<{ daily: ReviewDaily; day: string }>();
const days = computed(() => fillDays(props.daily.days, props.day));
const short = (day: string) =>
  new Date(`${day}T00:00:00Z`)
    .toLocaleDateString("en-GB", { day: "numeric", month: "short", timeZone: "UTC" })
    .toUpperCase();
/** The two worst days under target, annotated with what drove them. */
const dips = computed(() =>
  days.value
    .flatMap((d) => (d.entry ? [{ day: d, ratio: dayRatio(d.entry) ?? 1 }] : []))
    .filter((d) => d.ratio < props.daily.target)
    .sort((a, b) => a.ratio - b.ratio)
    .slice(0, 2)
    .map((d) => d.day),
);
function title(d: (typeof days.value)[number]): string {
  if (!d.entry) return `${short(d.day)} · no passes`;
  const e = d.entry;
  return `${short(d.day)} · ${percent(dayRatio(e))} realized · ${e.realized} of ${e.planned}${e.top_cause ? ` · ${causeText(e.top_cause)}` : ""}`;
}
</script>

<template>
  <ApPanel index="R3" title="Realization · 30 days" :meta="`Target ${percent(daily.target)}`">
    <div
      class="relative ml-10 h-40"
      role="img"
      :aria-label="`Daily realization for the 30 days to ${short(day)}: bar height is the share realized, 0 to 100%`"
    >
      <PercentTicks />
      <div
        class="absolute inset-x-0 border-t border-dashed border-readout"
        :style="{ bottom: `${daily.target * 100}%` }"
        aria-hidden="true"
      />
      <div class="flex h-full items-end gap-[2px]">
        <div
          v-for="d in days"
          :key="d.day"
          class="flex h-full min-w-0 flex-1 items-end"
          :title="title(d)"
        >
          <span
            v-if="d.entry"
            class="block w-full"
            :class="(dayRatio(d.entry) ?? 0) >= daily.target ? 'bg-nominal' : 'bg-caution'"
            :style="{ height: `${Math.max(2, (dayRatio(d.entry) ?? 0) * 100)}%` }"
          />
          <span v-else class="block h-[2px] w-full bg-hairline" />
        </div>
      </div>
    </div>
    <div class="mt-2 ml-10 flex justify-between font-mono text-xs text-text-3">
      <span>{{ short(days[0]?.day ?? day) }}</span>
      <span>{{ short(day) }}</span>
    </div>
    <ul
      v-if="dips.length > 0"
      class="m-0 mt-3 flex list-none flex-col gap-1 p-0 font-mono text-xs text-text-3 uppercase"
    >
      <li v-for="d in dips" :key="d.day">{{ title(d) }}</li>
    </ul>
  </ApPanel>
</template>
