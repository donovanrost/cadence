<script setup lang="ts">
/** One-line check summary: `IDENTITY GO · CATALOG GO · TWO-PERSON HOLD`. The word carries the verdict. */
export type ApVerdict = "go" | "hold" | "no_go" | "checking";
export type ApVerdictItem = Readonly<{ key: string; label: string; verdict: ApVerdict }>;
defineProps<{ items: readonly ApVerdictItem[]; label?: string | undefined }>();

const word: Record<ApVerdict, string> = {
  go: "GO",
  hold: "HOLD",
  no_go: "NO-GO",
  checking: "CHECKING…",
};
const tone: Record<ApVerdict, string> = {
  go: "text-nominal-text",
  hold: "text-caution-text",
  no_go: "text-crit-text",
  checking: "text-text-4",
};
</script>

<template>
  <ul
    :aria-label="label ?? 'Checks'"
    class="m-0 flex list-none flex-wrap items-center gap-x-2 gap-y-1 p-0 font-mono text-sm uppercase"
  >
    <li v-for="(item, i) in items" :key="item.key" class="flex items-center gap-2">
      <span v-if="i > 0" aria-hidden="true" class="text-text-4">·</span>
      <span class="text-text-3">{{ item.label }}</span>
      <span class="font-semibold" :class="tone[item.verdict]">{{ word[item.verdict] }}</span>
    </li>
  </ul>
</template>
