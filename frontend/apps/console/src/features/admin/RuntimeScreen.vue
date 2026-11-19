<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import {
  ApButton,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApStatusMark,
  ApTable,
  formatClock,
  useNow,
  type ApColumn,
} from "@/ui";
import { fetchRuntime } from "./api.ts";
import RuntimeDetails from "./RuntimeDetails.vue";
import { runtimeText, telemetryText, worstFirst } from "./present.ts";

/** Admin › Runtime (Admin.md): one row per mission, worst first; read-only diagnostics. */
const read = useRemoteQuery(() => true as const, fetchRuntime);
const now = useNow();
const updated = computed(() =>
  read.state.value.status === "ready"
    ? `Updated ${formatClock(new Date(read.state.value.value.observed_at))}`
    : undefined,
);
const columns: readonly ApColumn[] = [
  { key: "org", label: "Organization" },
  { key: "mission", label: "Mission" },
  { key: "runtime", label: "Runtime", mono: true },
  { key: "telemetry", label: "Telemetry last received" },
  { key: "details", label: "" },
];
</script>

<template>
  <ApPageHeader label="Platform admin · runtime" title="Runtime" size="reading">
    <span v-if="updated" class="font-mono text-xs text-text-3">{{ updated }}</span>
    <ApButton @click="read.refetch">Refresh</ApButton>
  </ApPageHeader>
  <ApPanel index="R1" title="Missions" flush>
    <ApRemote :state="read.state.value" loading-label="Loading runtime…" @retry="read.refetch">
      <template #default="{ value }">
        <ApTable
          :columns="columns"
          :rows="worstFirst(value.missions)"
          :row-key="(r) => r.mission.id"
          caption="Mission runtime"
        >
          <template #cell-org="{ row }">{{ row.organization.name }}</template>
          <template #cell-mission="{ row }">
            <a
              :href="`/console/${row.organization.slug}/${row.mission.slug}`"
              class="text-readout hover:underline"
              >{{ row.mission.name }}</a
            >
          </template>
          <template #cell-runtime="{ row }">
            <span class="inline-flex items-center gap-2"
              ><ApStatusMark :state="runtimeText(row.runtime).state" />{{
                runtimeText(row.runtime).text
              }}</span
            >
          </template>
          <template #cell-telemetry="{ row }">{{
            telemetryText(row.telemetry_last_received_at, now)
          }}</template>
          <template #cell-details="{ row }"><RuntimeDetails :row="row" /></template>
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
</template>
