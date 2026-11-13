<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute, useRouter, type LocationQueryValue } from "vue-router";
import { TakeoverHeader, useMissionScope, useSmallScreen } from "@/shell";
import { useConnection } from "@/live";
import { ApCallout } from "@/ui";
import type { Runtime } from "../api.ts";
import { recordView } from "../directory/api.ts";
import CopySheet from "../editor/CopySheet.vue";
import EditActions from "../editor/EditActions.vue";
import EditorPane from "../editor/EditorPane.vue";
import { useEditSession } from "../editor/useEditSession.ts";
import VersionsSheet from "../versions/VersionsSheet.vue";
import {
  selectionFromQuery,
  selectionLabel,
  selectionParams,
  type TimeSelection,
} from "../model/time-range.ts";
import KioskLine from "./KioskLine.vue";
import ViewerActions from "./ViewerActions.vue";
import ViewerBody from "./ViewerBody.vue";
import CockpitStatus from "./CockpitStatus.vue";
import { refreshChoices, useDashboardView, type RefreshChoice } from "./useDashboardView.ts";
import { useDashboardLive } from "./useDashboardLive.ts";

/**
 * Dashboard viewer and editor (ux Dashboards.md): a takeover cockpit. The URL owns the runtime
 * (`from`, `to`, `spacecraft`, `refresh`), kiosk and edit mode (`edit=1`). D5 resolves the view
 * (live step 1 refreshes on invalidations); edit mode previews the browser-held draft (D7) with
 * live values paused.
 */
const route = useRoute();
const router = useRouter();
const scope = useMissionScope();
const one = (v: LocationQueryValue | LocationQueryValue[] | undefined) =>
  typeof v === "string" ? v : "";
const missionId = computed(() => scope.value.mission.id);
const dashboardId = computed(() => one(route.params.dashboardId as LocationQueryValue));
const selection = computed(() => selectionFromQuery(one(route.query.from), one(route.query.to)));
const runtime = computed<Runtime>(() => {
  const params = selectionParams(selection.value);
  return {
    from: params.from ?? "",
    to: params.to ?? "",
    spacecraftId: one(route.query.spacecraft),
  };
});
const refresh = computed<RefreshChoice>(
  () => refreshChoices.find((c) => c.value === one(route.query.refresh))?.value ?? "2s",
);
const editRequested = computed(() => one(route.query.edit) === "1");
const refreshMs = computed(() => refreshChoices.find((c) => c.value === refresh.value)?.ms ?? null);
/** Live step 2 (C1, flagged): pushes drive the board; step 1's data refetch stands down meanwhile. */
const pushing = ref(false);
const query = useDashboardView(missionId, dashboardId, runtime, {
  refreshMs,
  sliding: computed(() => selection.value.kind !== "absolute"),
  paused: computed(() => editRequested.value || pushing.value),
});
const live = useDashboardLive(
  missionId,
  dashboardId,
  runtime,
  refreshMs,
  editRequested,
  computed(() => (query.state.value.status === "ready" ? query.state.value.value.snapshot : null)),
);
watch(live.active, (on) => (pushing.value = on));
// Someone saved, restored or archived it: re-read the head (current_version drives the editor's callout).
watch(live.version, () => query.refetch());
const shown = computed(() => {
  const s = query.state.value;
  return s.status === "ready" && live.active.value && live.snapshot.value
    ? { ...s, value: { ...s.value, snapshot: live.snapshot.value } }
    : s;
});
const view = computed(() => (shown.value.status === "ready" ? shown.value.value : null));
// D6: each open feeds the directory's "Recent". `request` resolves to a result (it never rejects),
// and a failed record changes nothing on this page, so the outcome is ignored on purpose.
watch(
  dashboardId,
  (id) => {
    if (id) void recordView(missionId.value, id);
  },
  { immediate: true },
);
const currentVersion = computed(() => view.value?.dashboard.current_version ?? null);
const session = useEditSession(missionId, dashboardId, runtime, currentVersion);
/** Phone is view-only (ux). */
const small = useSmallScreen();
const canEdit = computed(() => view.value?.can_edit === true && !small.value);
const editing = computed(() => editRequested.value && canEdit.value);
watch(
  [editing, () => view.value !== null],
  ([on, loaded]) => {
    if (on && loaded && !session.editing.value) session.enter();
    else if (!on && session.editing.value) session.leave();
  },
  { immediate: true },
);
const connection = useConnection();
/** Kiosk (ux): `?kiosk=1` or ⋯ › Kiosk; the header collapses to a status line. */
const kiosk = computed(() => one(route.query.kiosk) === "1");
const pane = ref<InstanceType<typeof EditorPane> | null>(null);
const versions = ref<InstanceType<typeof VersionsSheet> | null>(null);
const copySheet = ref<InstanceType<typeof CopySheet> | null>(null);
function onMenu(id: "versions" | "copy" | "kiosk") {
  if (id === "kiosk") setQuery({ kiosk: "1" });
  else if (id === "versions") versions.value?.open();
  else
    copySheet.value?.open(
      session.draft.value ?? { baseVersion: currentVersion.value ?? 1, commands: [] },
    );
}
function onDiscard() {
  session.discard();
  setQuery({ edit: null });
}
function onSaved() {
  setQuery({ edit: null });
  query.refetch();
}

function setQuery(changes: Record<string, string | null>) {
  const next = { ...route.query };
  for (const [k, v] of Object.entries(changes)) {
    if (v === null || v === "") delete next[k];
    else next[k] = v;
  }
  void router.replace({ query: next });
}
const onRange = (s: TimeSelection) =>
  setQuery({ from: null, to: null, ...selectionParams(s), time_mode: null });
</script>

<template>
  <KioskLine
    v-if="kiosk"
    :title="view?.dashboard.name ?? 'Dashboard'"
    :range="selectionLabel(selection)"
    @exit="setQuery({ kiosk: null })"
  />
  <TakeoverHeader
    v-else
    :title="view?.dashboard.name ?? 'Dashboard'"
    context="DASHBOARD"
    :close="{ name: 'ops.dashboards' }"
    close-label="Close dashboard"
    title-as="h1"
  >
    <template #actions>
      <EditActions
        v-if="editing"
        :changes="session.draft.value?.commands.length ?? 0"
        :busy="session.busy.value"
        @add="pane?.add()"
        @save="pane?.save()"
        @discard="onDiscard"
      />
      <ViewerActions
        v-else
        :scope-options="view?.scope_options ?? []"
        :spacecraft="runtime.spacecraftId"
        :selection="selection"
        :refresh="refresh"
        :can-edit="canEdit"
        @spacecraft="setQuery({ spacecraft: $event })"
        @range="onRange"
        @refresh="setQuery({ refresh: $event === '2s' ? null : $event })"
        @edit="setQuery({ edit: '1' })"
        @menu="onMenu"
      />
    </template>
    <template #clocks><CockpitStatus /></template>
  </TakeoverHeader>
  <ApCallout v-if="connection !== 'live'" tone="stale">
    Live connection lost. Values may be out of date; they'll refresh when it's back.
  </ApCallout>
  <EditorPane
    v-if="editing && view"
    ref="pane"
    :session="session"
    :view="view"
    :mission-id="missionId"
    @saved="onSaved"
  />
  <ViewerBody v-else :state="shown" :stale="connection !== 'live'" @retry="query.refetch" />
  <VersionsSheet
    ref="versions"
    :mission-id="missionId"
    :dashboard-id="dashboardId"
    :can-restore="canEdit && !editing"
    @restored="query.refetch"
  />
  <CopySheet
    ref="copySheet"
    :mission-id="missionId"
    :dashboard-id="dashboardId"
    :name="view?.dashboard.name ?? 'Dashboard'"
    @copied="session.discard"
  />
</template>
