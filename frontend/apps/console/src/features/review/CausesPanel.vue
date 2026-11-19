<script setup lang="ts">
import { computed } from "vue";
import { ApEmptyState, ApPanel } from "@/ui";
import type { CauseLine } from "./api.ts";
import { causeText, ownerWord } from "./format.ts";

/** R2 · Why passes were lost (or fell short, when none were missed): one bar per cause. */
const props = defineProps<{ causes: readonly CauseLine[] }>();
const lines = computed(() =>
  [...props.causes]
    .filter((c) => c.missed + c.partial > 0)
    .sort((a, b) => b.missed + b.partial - (a.missed + a.partial)),
);
const max = computed(() => Math.max(1, ...lines.value.map((c) => c.missed + c.partial)));
const width = (n: number) => `${(n / max.value) * 100}%`;
/** ux §7 #2: "lost" only when a pass was missed; partial-only reads "fell short". */
const title = computed(() =>
  props.causes.some((c) => c.missed > 0) ? "Why passes were lost" : "Why passes fell short",
);
</script>

<template>
  <ApPanel index="R2" :title="title" meta="By who owns the cause">
    <ApEmptyState
      v-if="lines.length === 0"
      state="off"
      headline="No passes lost"
      sentence="Every counted pass in this span was realized."
    />
    <template v-else>
      <ul class="m-0 flex list-none flex-col gap-3 p-0">
        <li
          v-for="c in lines"
          :key="`${c.cause}-${c.owner}`"
          :title="`${causeText(c.cause)}: ${c.missed} missed, ${c.partial} partial`"
          class="flex flex-col gap-1"
        >
          <div class="flex items-baseline justify-between gap-3 text-sm">
            <span class="text-text-2">{{ causeText(c.cause) }}</span>
            <span class="font-mono text-xs text-text-3 uppercase"
              >{{ ownerWord[c.owner] }} · {{ c.missed + c.partial }}</span
            >
          </div>
          <div class="flex h-2 gap-[2px]" aria-hidden="true">
            <span v-if="c.missed > 0" class="h-full bg-crit" :style="{ width: width(c.missed) }" />
            <span
              v-if="c.partial > 0"
              class="h-full bg-caution"
              :style="{ width: width(c.partial) }"
            />
          </div>
        </li>
      </ul>
      <p class="m-0 mt-4 flex gap-4 font-mono text-xs text-text-3 uppercase">
        <span class="inline-flex items-center gap-1.5"
          ><span class="size-2 bg-crit" aria-hidden="true" />Missed</span
        >
        <span class="inline-flex items-center gap-1.5"
          ><span class="size-2 bg-caution" aria-hidden="true" />Partial</span
        >
      </p>
    </template>
  </ApPanel>
</template>
