<script setup lang="ts">
import { computed } from "vue";
import type { WorkspacePlacement } from "../../workspace/contracts";
import { events, formatTime } from "../widget-data";

const props = defineProps<{ placement: WorkspacePlacement }>();
const rows = computed(() => events(props.placement));
const dot = (severity: string | null) =>
  severity === "critical" || severity === "error"
    ? "bg-error"
    : severity === "warning"
      ? "bg-warning"
      : "bg-info";
</script>

<template>
  <ol class="h-full min-h-0 space-y-2 overflow-auto px-3 py-2">
    <li v-for="row in rows" :key="row.key" class="flex gap-2.5">
      <span
        class="mt-1.5 h-2 w-2 shrink-0 rounded-full"
        :class="dot(row.severity)"
        aria-hidden="true"
      ></span>
      <div class="min-w-0">
        <p class="break-words text-sm">{{ row.title }}</p>
        <p class="flex flex-wrap gap-x-2 font-mono text-xs text-base-content/60">
          <time>{{ formatTime(row.at) }}</time>
          <span v-if="row.category">{{ row.category }}</span>
          <span v-if="row.severity">{{ row.severity }}</span>
          <span v-if="row.ends !== null">until {{ formatTime(row.ends) }}</span>
        </p>
      </div>
    </li>
  </ol>
</template>
