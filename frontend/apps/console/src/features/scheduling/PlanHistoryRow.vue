<script setup lang="ts">
import { ref } from "vue";
import { useRoute } from "vue-router";
import { ApButton, ApTag } from "@/ui";
import type { HistoryLine } from "./plan-history.ts";

/** One row of a plan's history (U73): the line, its tags, a quote, counts, Show and View R3. */
defineProps<{ row: HistoryLine }>();
const route = useRoute();
const shown = ref(false);
const showSkipped = ref(false);
</script>

<template>
  <li class="flex flex-col gap-1 border-b border-hairline py-2.5 last:border-b-0">
    <span class="flex flex-wrap items-center gap-x-2 gap-y-1 text-md text-text">
      <span>{{ row.line }}</span>
      <ApTag v-for="t in row.tags" :key="t.label" :label="t.label" :state="t.state ?? undefined" />
      <ApButton
        v-if="row.detailsLabel"
        variant="ghost"
        size="compact"
        :aria-expanded="shown"
        @click="shown = !shown"
        >{{ shown ? "Hide" : row.detailsLabel }}</ApButton
      >
      <ApButton
        v-if="row.skipped"
        variant="ghost"
        size="compact"
        :aria-expanded="showSkipped"
        @click="showSkipped = !showSkipped"
        >{{ showSkipped ? "Hide" : row.skipped.label }}</ApButton
      >
      <ApButton
        v-if="row.view !== null"
        variant="ghost"
        size="compact"
        :to="{ name: 'ops.contacts.plan', query: { ...route.query, version: String(row.view) } }"
        >View R{{ row.view }}</ApButton
      >
    </span>
    <span v-if="row.quote" class="text-sm text-text-2">{{ row.quote }}</span>
    <!-- #273: the passes this approval skipped because their booking window had closed. -->
    <ul
      v-if="showSkipped && row.skipped"
      class="m-0 flex list-none flex-col gap-0.5 p-0 font-mono text-sm text-text-2 tabular"
    >
      <li v-for="(line, i) in row.skipped.lines" :key="i">{{ line }}</li>
      <li v-if="row.skipped.capped" class="font-sans text-text-3">{{ row.skipped.capped }}</li>
    </ul>
    <span v-if="row.counts" class="font-mono text-sm text-text-3 tabular">{{ row.counts }}</span>
    <!-- ux U73 / design-language §8: no raw id leads a row; reasons, ids under Technical details. -->
    <template v-if="shown">
      <ul class="m-0 flex list-none flex-col gap-0.5 p-0 text-sm text-text-2">
        <li v-for="(d, i) in row.details" :key="i">{{ d.text }}</li>
      </ul>
      <details class="text-sm text-text-3">
        <summary class="cursor-pointer">Technical details</summary>
        <ul class="m-0 mt-1 flex list-none flex-col gap-0.5 p-0 font-mono text-xs">
          <li v-for="(d, i) in row.details" :key="i">{{ d.id }}</li>
        </ul>
      </details>
    </template>
  </li>
</template>
