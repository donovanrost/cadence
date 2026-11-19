<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApSegmented } from "@/ui";
import ImportRunsPanel from "./ImportRunsPanel.vue";
import RevisionsPanel from "./RevisionsPanel.vue";
import { fetchCatalogIndex, revisionSummary } from "./api.ts";

/** Setup › Catalog (rail 04). Spec: docs/apogee/ux/screens/Catalog.md § A. */
const scope = useMissionScope();
const session = useSession();
const canManage = computed(() => canAdministerOrganization(session, scope.value.organization));
/** `?database=` (the old `setup/catalog/:databaseId` path redirects here, ux §7 #8). */
const initial = useRoute().query["database"];
const databaseId = ref<string | null>(typeof initial === "string" && initial ? initial : null);
const key = computed(() => ({ missionId: scope.value.mission.id, databaseId: databaseId.value }));
const { state, refetch } = useRemoteQuery(key, fetchCatalogIndex);
useMissionInvalidation(
  computed(() => scope.value.mission.id),
  ["catalog"],
  refetch,
);

const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const title = computed(() => {
  const s = state.value;
  if (s.status !== "ready") return "Catalog";
  const rev = s.value.database?.current_revision;
  return rev ? `Catalog revision ${rev.number}` : "No catalog yet";
});
const selected = computed({
  get: () => (state.value.status === "ready" ? (state.value.value.database?.id ?? "") : ""),
  set: (value: string) => {
    databaseId.value = value;
  },
});
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader :label="`${scope.mission.name} · catalog`" :title="title" size="reading">
      <template v-if="state.status === 'ready' && state.value.database?.current_revision" #subtitle>
        <span class="text-md text-text-3">{{
          revisionSummary(state.value.database.current_revision)
        }}</span>
      </template>
      <ApButton v-if="canManage" variant="primary" :to="{ name: 'setup.catalog.import' }"
        >Import a new revision</ApButton
      >
    </ApPageHeader>
    <ApPanel v-if="notProvided" index="A1" title="Revisions" flush>
      <ApEmptyState
        state="off"
        headline="Catalog not available in the console yet"
        sentence="This server doesn't serve the catalog to the console yet. Revisions and imports appear here when it does."
      />
    </ApPanel>
    <ApRemote v-else :state="state" loading-label="Loading catalog…" @retry="refetch">
      <template #default="{ value }">
        <ApSegmented
          v-if="value.databases.length > 1"
          v-model="selected"
          :options="value.databases.map((d) => ({ value: d.id, label: d.name }))"
          label="Catalog database"
        />
        <ApPanel v-if="value.database === null" index="A1" title="Revisions" flush>
          <ApEmptyState
            state="off"
            headline="No catalog yet"
            sentence="Commands and telemetry come from an XTCE or CSV export of your flight software database."
          />
        </ApPanel>
        <template v-else>
          <RevisionsPanel :revisions="value.database.revisions" />
          <ImportRunsPanel
            v-if="value.database.import_runs.length > 0"
            :runs="value.database.import_runs"
          />
        </template>
      </template>
    </ApRemote>
  </div>
</template>
