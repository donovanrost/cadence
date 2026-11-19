<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { FailureOutcomeCallout, type RefusalOutcome } from "@/features/changes/index.ts";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApButton, ApEmptyState, ApPanel, ApRemote, type ApColumn } from "@/ui";
import { fetchTransports } from "./api.ts";
import TransportsTable from "./TransportsTable.vue";

/** Transports (rail 05 tab). Adds and edits stage into the change set (transport kind). */
const scope = useMissionScope();
const session = useSession();
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
/** ux U82: archived transports are hidden unless asked for, listed after the active ones. */
const showArchived = ref(false);
const { state, refetch } = useRemoteQuery(
  () => ({ missionId: scope.value.mission.id, archived: showArchived.value }),
  (key, signal) => fetchTransports(key.missionId, signal, key.archived),
);
/** U82: an in-use refusal, shown in place of the confirm with what still uses it. */
const refused = ref<RefusalOutcome | null>(null);
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
    <template #header>
      <label class="flex items-center gap-2 text-sm text-text-2">
        <input
          v-model="showArchived"
          type="checkbox"
          class="size-4 accent-[var(--color-readout)]"
        />
        Show archived
      </label>
      <ApButton
        v-if="canStage"
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
        <template v-else>
          <FailureOutcomeCallout v-if="refused" :outcome="refused" class="m-4" />
          <TransportsTable
            :mission-id="scope.mission.id"
            :rows="value"
            :columns="columns"
            :can-stage="canStage"
            @refused="refused = $event"
          />
        </template>
      </template>
    </ApRemote>
  </ApPanel>
</template>
