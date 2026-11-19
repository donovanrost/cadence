<script setup lang="ts">
import { computed } from "vue";
import { ApStatusMark, type OpState } from "@/ui";
import type { WorkspacePlacement } from "../model/snapshot.ts";
import { events, formatTime } from "../model/widget-data.ts";

const props = defineProps<{ placement: WorkspacePlacement }>();
const rows = computed(() => events(props.placement));
const mark = (severity: string | null): OpState =>
  severity === "critical" || severity === "error"
    ? "crit"
    : severity === "warning"
      ? "caution"
      : "neutral";
</script>

<template>
  <ol class="h-full min-h-0 space-y-2 overflow-auto px-3 py-2">
    <li v-for="row in rows" :key="row.key" class="flex gap-2.5">
      <span class="mt-1.5"><ApStatusMark :state="mark(row.severity)" /></span>
      <div class="min-w-0">
        <p class="break-words text-md text-readout">{{ row.title }}</p>
        <p class="flex flex-wrap gap-x-2 font-mono text-xs text-text-4">
          <time>{{ formatTime(row.at) }}</time>
          <span v-if="row.category">{{ row.category }}</span>
          <span v-if="row.severity">{{ row.severity }}</span>
          <span v-if="row.ends !== null">until {{ formatTime(row.ends) }}</span>
        </p>
      </div>
    </li>
  </ol>
</template>
