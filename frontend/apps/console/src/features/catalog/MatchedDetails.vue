<script setup lang="ts">
import { computed } from "vue";
import { ApKeyValue, ApPanel } from "@/ui";
import type { MatchedRevision } from "./matchedRevision.ts";
import { resultText } from "./matchedWords.ts";

/** U99 Technical details: the run's result as sent and the mission model revision id. */
const props = defineProps<{ match: MatchedRevision }>();
const items = computed(() => [
  { key: "result", label: "Run result", value: resultText(props.match), mono: true },
  {
    key: "model",
    label: "Mission model revision",
    value: props.match.model_revision_id,
    mono: true,
  },
]);
</script>

<template>
  <ApPanel title="Technical details"><ApKeyValue :items="items" :columns="2" /></ApPanel>
</template>
