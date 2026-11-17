<script setup lang="ts">
import { computed } from "vue";
import { ApStatusMark, ApTag } from "@/ui";
import type { Comparison } from "./api.ts";
import { replayLine, riskTag, sectionLine, verdictLine, verdictState } from "./words.ts";

/** ux U65 report body: verdict, failing parts, risk, replay, one line per changed kind. */
const props = defineProps<{ report: Comparison }>();
const risk = computed(() => riskTag(props.report));
const lines = computed(() =>
  props.report.sections.map(sectionLine).filter((l): l is string => l !== null),
);
const replay = computed(() => replayLine(props.report));
</script>

<template>
  <div class="flex flex-col gap-2">
    <p class="m-0 flex items-center gap-2 text-base text-readout">
      <ApStatusMark :state="verdictState(report)" />{{ verdictLine(report) }}
      <ApTag :state="risk.state" :label="risk.label" />
    </p>
    <ul v-if="report.replay.failed_cases.length" class="m-0 list-none p-0 text-md text-text-2">
      <li v-for="c in report.replay.failed_cases" :key="c.name">
        <span class="font-mono">{{ c.name }}</span
        ><template v-if="c.reason">: {{ c.reason }}</template>
      </li>
    </ul>
    <p v-if="replay" class="m-0 text-md text-text-2">{{ replay }}</p>
    <ul v-if="lines.length" class="m-0 list-none p-0 text-md text-text-2">
      <li v-for="l in lines" :key="l">{{ l }}</li>
    </ul>
    <p v-else class="m-0 text-md text-text-3">No declarations changed.</p>
  </div>
</template>
