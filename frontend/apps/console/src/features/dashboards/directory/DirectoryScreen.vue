<script setup lang="ts">
import { computed, ref } from "vue";
import { RouterLink } from "vue-router";
import { organizationCapabilities, useMissionScope, useSession } from "@/shell";
import { ApButton, ApCallout, ApEmptyState, ApPageHeader, ApRemote } from "@/ui";
import { setStarred, unarchive, type DirectoryRow } from "./api.ts";
import ArchiveSheet from "./ArchiveSheet.vue";
import DirectoryTable from "./DirectoryTable.vue";
import DirectoryToolbar from "./DirectoryToolbar.vue";
import DuplicateSheet from "./DuplicateSheet.vue";
import TelemetryTabs from "./TelemetryTabs.vue";
import { useDirectory } from "./useDirectory.ts";
import { refetchKeepingFocus } from "../focus-fallback.ts";

/** Ops › Telemetry › Dashboards (ux Dashboards.md): a normal reading page in the shell. */
const scope = useMissionScope();
const session = useSession();
const missionId = computed(() => scope.value.mission.id);
const { query, listing, set } = useDirectory(missionId);
/** D0: authoring is the mission's organization's `dashboard.author` (session.md). */
const canEdit = computed(() =>
  organizationCapabilities(session, scope.value.organization).has("dashboard.author"),
);
const archiveSheet = ref<InstanceType<typeof ArchiveSheet> | null>(null);
const duplicateSheet = ref<InstanceType<typeof DuplicateSheet> | null>(null);
const failure = ref<string | null>(null);
const refetchRows = refetchKeepingFocus(() => listing.state.value, listing.refetch);
const filtered = computed(
  () =>
    query.value.q !== "" ||
    query.value.tags.length > 0 ||
    query.value.starred ||
    query.value.archived,
);

async function onAction(
  action: "star" | "unstar" | "duplicate" | "archive" | "restore",
  row: DirectoryRow,
) {
  failure.value = null;
  if (action === "archive") return archiveSheet.value?.open(row);
  if (action === "duplicate") return duplicateSheet.value?.open(row);
  const result =
    action === "restore"
      ? await unarchive(missionId.value, row.id)
      : await setStarred(missionId.value, row.id, action === "star");
  if (result.ok) refetchRows();
  else
    failure.value = result.error.kind === "unauthenticated" ? "Signed out." : result.error.message;
}
</script>

<template>
  <ApPageHeader :label="`${scope.mission.name} · telemetry`" title="Dashboards" size="reading">
    <!-- ux § Where it sits: Library · Playlists · New dashboard; wraps under the h1 on a phone. -->
    <span class="flex flex-wrap gap-2">
      <ApButton variant="secondary" :to="{ name: 'ops.dashboards.library' }">Library</ApButton>
      <ApButton variant="secondary" :to="{ name: 'ops.dashboards.playlists' }">Playlists</ApButton>
      <ApButton v-if="canEdit" variant="primary" :to="{ name: 'ops.dashboards.new' }"
        >New dashboard</ApButton
      >
    </span>
  </ApPageHeader>
  <TelemetryTabs active="dashboards" />
  <DirectoryToolbar
    :query="query"
    :tags="listing.state.value.status === 'ready' ? listing.state.value.value.available_tags : []"
    @set="set"
  />
  <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
  <ApRemote :state="listing.state.value" @retry="listing.refetch">
    <template #default="{ value }">
      <p
        v-if="value.shortcuts.recent.length && !filtered"
        class="m-0 flex flex-wrap gap-x-3 text-sm text-text-3"
      >
        <span class="font-display text-xs uppercase tracking-label text-text-4">Recent</span>
        <RouterLink
          v-for="r in value.shortcuts.recent.slice(0, 6)"
          :key="r.id"
          :to="{ name: 'ops.dashboard', params: { dashboardId: r.id } }"
          class="text-readout hover:underline"
          >{{ r.name }}</RouterLink
        >
      </p>
      <ApEmptyState
        v-if="value.dashboards.length === 0"
        :headline="filtered ? 'No dashboards match.' : 'No dashboards yet.'"
        :announce="filtered"
        :sentence="
          filtered
            ? 'Clear the search or filters to see them all.'
            : canEdit
              ? 'Create one with New dashboard.'
              : 'Someone with dashboard authoring access can create one.'
        "
      />
      <DirectoryTable v-else :rows="value.dashboards" :can-edit="canEdit" @action="onAction" />
      <p v-if="value.pages > 1" class="m-0 flex items-center gap-3 text-sm text-text-3">
        <ApButton
          size="compact"
          variant="secondary"
          :disabled="value.page <= 1"
          disabled-reason="First page."
          @click="set({ page: String(value.page - 1) })"
          >Previous</ApButton
        >
        Page {{ value.page }} of {{ value.pages }} · {{ value.total }} dashboards
        <ApButton
          size="compact"
          variant="secondary"
          :disabled="value.page >= value.pages"
          disabled-reason="Last page."
          @click="set({ page: String(value.page + 1) })"
          >Next</ApButton
        >
      </p>
    </template>
  </ApRemote>
  <ArchiveSheet ref="archiveSheet" :mission-id="missionId" @done="refetchRows" />
  <DuplicateSheet ref="duplicateSheet" :mission-id="missionId" />
</template>
