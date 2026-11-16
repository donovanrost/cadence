<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import {
  ApButton,
  ApEmptyState,
  ApPanel,
  ApRemote,
  ApTable,
  formatCount,
  type ApColumn,
} from "@/ui";
import { directionLabel, fetchTransports } from "./api.ts";

/** Transports (rail 05 tab). Adds and edits stage into the change set (transport kind). */
const scope = useMissionScope();
const session = useSession();
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
const { state, refetch } = useRemoteQuery(() => scope.value.mission.id, fetchTransports);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const allColumns: readonly ApColumn[] = [
  { key: "name", label: "Transport" },
  { key: "station", label: "Station" },
  { key: "direction", label: "Direction" },
  { key: "origin", label: "Origin" },
  { key: "rules", label: "Routing rules", mono: true, align: "end" },
];
// U10: the model has no station↔transport link yet, so the column is left out while all null.
const columns = computed(() =>
  state.value.status === "ready" && state.value.value.some((t) => t.station !== null)
    ? allColumns
    : allColumns.filter((c) => c.key !== "station"),
);
</script>

<template>
  <ApPanel index="T1" title="Transports" flush>
    <template v-if="canStage" #header>
      <ApButton
        size="compact"
        :to="{ name: 'setup.comms.transports', params: { transportId: 'new' } }"
        >Add transport</ApButton
      >
    </template>
    <ApEmptyState
      v-if="notProvided"
      state="off"
      headline="Transports not available in the console yet"
      sentence="This server doesn't serve transports to the console yet."
    />
    <ApRemote v-else :state="state" loading-label="Loading transports…" @retry="refetch">
      <template #default="{ value }">
        <ApEmptyState v-if="value.length === 0" state="off" headline="No transports yet" />
        <ApTable
          v-else
          :columns="columns"
          :rows="value"
          :row-key="(t) => t.id"
          caption="Transports"
        >
          <template #cell-name="{ row }">
            <RouterLink
              :to="{ name: 'setup.comms.transports', params: { transportId: row.id } }"
              class="font-semibold text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
              >{{ row.display_name }}</RouterLink
            >
            <span class="font-mono text-xs text-text-4"> v{{ row.version }}</span>
          </template>
          <template #cell-station="{ row }">{{ row.station?.display_name ?? "—" }}</template>
          <template #cell-direction="{ row }">{{
            directionLabel(row.direction_capability)
          }}</template>
          <template #cell-origin="{ row }">{{
            row.origin === "direct" ? "Direct" : "Provider managed"
          }}</template>
          <template #cell-rules="{ row }">{{ formatCount(row.routing_rule_count) }}</template>
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
</template>
