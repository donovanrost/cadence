<script setup lang="ts">
import { computed } from "vue";
import { formatCount, ApTag, stateInsetClass } from "@/ui";
import type { ReadinessArea } from "./api.ts";
import { areaName, areaRoute, areaState, areaWord } from "./present.ts";

/** One readiness area: name (the link) + status tag, big number + unit, one-line detail. */
const props = defineProps<{ area: ReadinessArea }>();
const state = computed(() => areaState(props.area.status));
</script>

<template>
  <div class="flex flex-col gap-2 bg-panel px-4 py-3.5" :class="stateInsetClass(state)">
    <div class="flex items-center justify-between gap-3">
      <RouterLink
        :to="areaRoute(area.key)"
        class="font-display text-[17px] font-semibold tracking-title text-readout uppercase no-underline hover:text-bright hover:underline max-md:hit-44"
        >{{ areaName(area.key) }}</RouterLink
      >
      <ApTag size="tile" :state="state" :label="areaWord(area.status)" />
    </div>
    <span class="flex flex-wrap items-baseline gap-x-2 font-sans">
      <span class="text-[28px] leading-none font-medium tabular">
        <template v-if="area.count !== null">{{ formatCount(area.count) }}</template>
        <template v-else
          ><span aria-hidden="true" class="text-text-4">—</span
          ><span class="sr-only">unknown</span></template
        >
      </span>
      <span class="text-base text-text-4">{{ area.unit }}</span>
      <span v-if="area.secondary" class="text-base text-text-4"
        >· {{ formatCount(area.secondary.count) }} {{ area.secondary.unit }}</span
      >
    </span>
    <span v-if="area.detail" class="text-[13px] text-text-3">{{ area.detail }}</span>
  </div>
</template>
