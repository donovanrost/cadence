<script setup lang="ts">
import type { DashboardId } from "@/api/index.ts";
import { ApEmptyState, ApPanel, ApTable, type ApColumn } from "@/ui";
import type { Snapshot } from "./api.ts";
import { byLine, routerPath, snapshotWindow, visibilityWord } from "./present.ts";

/** Snapshots (ux): read-only; taken from the viewer, never here; no Delete until domain's Q6 batch. */
defineProps<{ dashboardId: DashboardId; snapshots: readonly Snapshot[] }>();
const columns: readonly ApColumn[] = [
  { key: "window", label: "Window", mono: true },
  { key: "version", label: "Version", mono: true },
  { key: "data", label: "Data" },
  { key: "taken", label: "Taken" },
];
</script>

<template>
  <ApPanel index="S4" title="Snapshots" flush>
    <p class="m-0 px-4 pt-3 text-md text-text-3">
      Take a snapshot from the dashboard: set the range, then
      <RouterLink
        :to="{ name: 'ops.dashboard', params: { dashboardId } }"
        class="text-readout hover:underline"
        >⋯ › Take snapshot</RouterLink
      >.
    </p>
    <ApEmptyState v-if="snapshots.length === 0" headline="No snapshots" />
    <ApTable v-else :columns="columns" :rows="snapshots" :row-key="(s) => s.id" caption="Snapshots">
      <template #cell-window="{ row }">
        <RouterLink :to="routerPath(row.url)" class="text-readout hover:underline">{{
          snapshotWindow(row)
        }}</RouterLink>
      </template>
      <template #cell-version="{ row }">v{{ row.version }}</template>
      <template #cell-data="{ row }">{{ visibilityWord(row.data_visibility) }}</template>
      <template #cell-taken="{ row }"
        ><span class="text-text-2">{{ byLine(row.created_by, row.created_at) }}</span></template
      >
    </ApTable>
  </ApPanel>
</template>
