<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import {
  ApBreadcrumb,
  ApButton,
  ApEmptyState,
  ApPageHeader,
  ApRemote,
  ApTable,
  formatShort,
  type ApColumn,
  type ApCrumb,
} from "@/ui";
import TelemetryTabs from "../directory/TelemetryTabs.vue";
import MoreMenu from "../viewer/MoreMenu.vue";
import { fetchPlaylists, type PlaylistSummary } from "./api.ts";
import DeleteSheet from "./DeleteSheet.vue";
import PlaylistSheet from "./PlaylistSheet.vue";
import { focusLost, refetchKeepingFocus } from "../focus-fallback.ts";

/** Playlists (ux): Name · Dashboards · Dwell · Updated · Present; editor and delete in sheets. */
const scope = useMissionScope();
/** ux § Where it sits: Playlists belongs to Dashboards, so it crumbs back to the directory. */
const crumbs: readonly ApCrumb[] = [
  { label: "Dashboards", to: { name: "ops.dashboards" } },
  { label: "Playlists" },
];
const missionId = computed(() => scope.value.mission.id);
const list = useRemoteQuery(missionId, (id, signal) => fetchPlaylists(id, "", signal));
useMissionInvalidation(missionId, ["dashboards"], list.refetch);
const editor = ref<InstanceType<typeof PlaylistSheet> | null>(null);
const remover = ref<InstanceType<typeof DeleteSheet> | null>(null);
const refetchRows = refetchKeepingFocus(() => list.state.value, list.refetch);
/** Back from Present (Esc or Exit, which pass `presentFocus`): its Present link takes focus (ux). */
const state: unknown = window.history.state;
let returnTo =
  state &&
  typeof state === "object" &&
  "presentFocus" in state &&
  typeof state.presentFocus === "string"
    ? state.presentFocus
    : null;
watch(
  () => list.state.value.status,
  async (status) => {
    if (status !== "ready" || returnTo === null) return;
    const id = returnTo;
    returnTo = null;
    await nextTick();
    const link = document.querySelector<HTMLElement>(`[data-present="${CSS.escape(id)}"]`);
    // The shell may have put focus on the h1 meanwhile; anything else the user chose stays.
    const active = document.activeElement;
    if (focusLost() || active?.tagName === "H1") link?.focus();
  },
  { immediate: true, flush: "post" },
);
const canEdit = computed(
  () => list.state.value.status === "ready" && list.state.value.value.can_edit,
);
const columns: readonly ApColumn[] = [
  { key: "name", label: "Name" },
  { key: "dashboards", label: "Dashboards", align: "end", mono: true },
  { key: "dwell", label: "Dwell", align: "end", mono: true },
  { key: "updated", label: "Updated", mono: true },
  { key: "actions", label: "Actions", hiddenLabel: true, align: "end" },
];
const items = [
  { id: "edit" as const, label: "Edit…" },
  { id: "delete" as const, label: "Delete…" },
];
function onAction(id: "edit" | "delete", p: PlaylistSummary) {
  if (id === "edit") void editor.value?.open(p);
  else remover.value?.open(p);
}
</script>

<template>
  <ApBreadcrumb :crumbs="crumbs" />
  <ApPageHeader :label="`${scope.mission.name} · dashboards`" title="Playlists" size="reading">
    <ApButton v-if="canEdit" variant="primary" @click="editor?.open(null)">New playlist</ApButton>
  </ApPageHeader>
  <TelemetryTabs active="dashboards" />
  <ApRemote :state="list.state.value" @retry="list.refetch">
    <template #default="{ value }">
      <ApEmptyState
        v-if="value.playlists.length === 0"
        headline="No playlists yet."
        :sentence="
          value.can_edit
            ? 'A playlist rotates dashboards on a wall screen. Create one with New playlist.'
            : 'Someone with dashboard authoring access can create one.'
        "
      />
      <ApTable
        v-else
        :columns="columns"
        :rows="value.playlists"
        :row-key="(r) => r.id"
        caption="Playlists"
      >
        <template #cell-name="{ row }"
          ><span class="text-readout">{{ row.name }}</span></template
        >
        <template #cell-dashboards="{ row }">{{ row.dashboard_count }}</template>
        <template #cell-dwell="{ row }">{{ row.dwell_seconds }} s</template>
        <template #cell-updated="{ row }"
          ><span class="text-text-3">{{
            row.updated_at ? formatShort(new Date(row.updated_at)) : "—"
          }}</span></template
        >
        <template #cell-actions="{ row }">
          <span class="flex items-center justify-end gap-2">
            <ApButton
              size="compact"
              variant="secondary"
              :to="{ name: 'ops.dashboards.present', params: { playlistId: row.id } }"
              :data-present="row.id"
              >Present</ApButton
            >
            <MoreMenu
              v-if="value.can_edit"
              :items="items"
              :label="`Actions for ${row.name}`"
              @select="(a) => onAction(a, row)"
            />
          </span>
        </template>
      </ApTable>
    </template>
  </ApRemote>
  <PlaylistSheet ref="editor" :mission-id="missionId" @saved="list.refetch" />
  <DeleteSheet ref="remover" :mission-id="missionId" @deleted="refetchRows" />
</template>
