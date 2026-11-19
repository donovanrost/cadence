<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import { useRoute, useRouter, type LocationQueryValue } from "vue-router";
import { TakeoverHeader, useMissionScope, useSmallScreen } from "@/shell";
import { useConnection } from "@/live";
import { announcePolite, ApButton, ApCallout } from "@/ui";
import type { Runtime } from "../api.ts";
import { recordView } from "../directory/api.ts";
import { exportUrl } from "../settings/api.ts";
import CopySheet from "../editor/CopySheet.vue";
import EditActions from "../editor/EditActions.vue";
import EditorPane from "../editor/EditorPane.vue";
import type { SourceWarning } from "../editor/contracts.ts";
import { warningsText } from "../editor/source-warnings.ts";
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
import SnapshotSheet from "./SnapshotSheet.vue";
import ViewerBody from "./ViewerBody.vue";
import CockpitStatus from "./CockpitStatus.vue";
import PhoneStatusBar from "./PhoneStatusBar.vue";
import ViewerControls from "./ViewerControls.vue";
import { refreshChoices, useDashboardView, type RefreshChoice } from "./useDashboardView.ts";
import { liveSnapshot } from "../model/live-merge.ts";
import { LIVE_PUSH, useDashboardLive } from "./useDashboardLive.ts";
import { refocus } from "../focus-fallback.ts";

/**
 * Dashboard viewer and editor (ux Dashboards.md): a takeover cockpit. The URL owns the runtime
 * (`from`, `to`, `spacecraft`, `refresh`), kiosk and edit mode (`edit=1`). D5 resolves the view
 * (live step 1 refreshes on invalidations); edit mode previews the browser-held draft (D7) with
 * live values paused.
 */
const route = useRoute("ops.dashboard");
const router = useRouter();
const scope = useMissionScope();
const one = (v: LocationQueryValue | LocationQueryValue[] | undefined) =>
  typeof v === "string" ? v : "";
const missionId = computed(() => scope.value.mission.id);
const dashboardId = computed(() => route.params.dashboardId);
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
/** D5 loads the head and the first board; with C1 on, data comes over the channel (step 1 retired). */
const query = useDashboardView(missionId, dashboardId, runtime, {
  refreshMs,
  sliding: computed(() => selection.value.kind !== "absolute"),
  paused: computed(() => editRequested.value || LIVE_PUSH),
});
const live = useDashboardLive(missionId, dashboardId, runtime, refreshMs, editRequested);
// Someone saved, restored or archived it: re-read the head (current_version drives the editor's callout).
watch(live.version, () => query.refetch());
const shown = computed(() => {
  const s = query.state.value;
  const pushed =
    s.status === "ready" ? liveSnapshot(live.board.value, s.value.dashboard.current_version) : null;
  return s.status === "ready" && pushed ? { ...s, value: { ...s.value, snapshot: pushed } } : s;
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
watch(live.version, (v) => {
  if (v)
    session.noteSaved({
      currentVersion: v.current_version,
      savedBy: v.saved_by?.name ?? null,
      savedAt: v.saved_at,
    });
});
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
/**
 * The header swaps its actions on Edit, Save, Discard and entering or leaving kiosk, taking the
 * focused control with it (a11y A5): focus lands on the counterpart (Add widget; Edit, else ⋯;
 * Exit kiosk), as ux asks for kiosk ('after Esc, focus returns to ⋯ › Kiosk').
 */
const headerControl = (selector: string) => document.querySelector<HTMLElement>(selector);
const viewerMenu = "[data-viewer-menu] [aria-haspopup]";
watch(
  [editing, kiosk],
  async ([on, inKiosk], [wasOn, wasKiosk]) => {
    await nextTick();
    if (on && !wasOn) refocus(headerControl("[data-add-widget]"));
    else if (inKiosk && !wasKiosk) refocus(headerControl("[data-exit-kiosk]"));
    else if (wasKiosk && !inKiosk) refocus(headerControl(viewerMenu));
    else if (wasOn && !on)
      refocus(headerControl("[data-edit-dashboard]") ?? headerControl(viewerMenu));
  },
  { flush: "post" },
);
const pane = ref<InstanceType<typeof EditorPane> | null>(null);
const versions = ref<InstanceType<typeof VersionsSheet> | null>(null);
const copySheet = ref<InstanceType<typeof CopySheet> | null>(null);
const snapshotSheet = ref<InstanceType<typeof SnapshotSheet> | null>(null);
function onMenu(
  id: "versions" | "settings" | "activity" | "copy" | "snapshot" | "export" | "kiosk",
) {
  switch (id) {
    case "kiosk":
      return setQuery({ kiosk: "1" });
    case "versions":
      return versions.value?.open();
    case "snapshot":
      return snapshotSheet.value?.open();
    case "export":
      // A plain download (the server records the export); ux's toast waits for a kit toast. B6:
      // until then, a screen reader hears that it started. Only that: the console can't see
      // whether the browser saves the file (U20), nor its name (the server sets it).
      download(exportUrl({ missionId: missionId.value, dashboardId: dashboardId.value }));
      return announcePolite("Export started.");
    case "settings":
    case "activity":
      return router.push({
        name: "ops.dashboard.settings",
        params: { dashboardId: dashboardId.value, tab: id === "settings" ? "general" : "activity" },
      });
    case "copy":
      return copySheet.value?.open(
        session.draft.value ?? { baseVersion: currentVersion.value ?? 1, commands: [] },
      );
  }
}
function download(href: string) {
  const link = document.createElement("a");
  link.href = href;
  link.download = "";
  link.click();
}
function onDiscard() {
  session.discard();
  setQuery({ edit: null });
}
/** A write went through but a source wasn't answering (api): said once, until dismissed or edited. */
const sourceNote = ref<string | null>(null);
// Cleared on another dashboard or a new edit; leaving edit mode is how a save lands, so not then.
watch(dashboardId, () => (sourceNote.value = null));
watch(editing, (now) => {
  if (now) sourceNote.value = null;
});
function onSaved(warnings: readonly SourceWarning[]) {
  setQuery({ edit: null });
  query.refetch();
  sourceNote.value = warningsText("Saved.", warnings);
}
function onRestored(warnings: readonly SourceWarning[]) {
  query.refetch();
  sourceNote.value = warningsText("Restored.", warnings);
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
    :clock="!small"
  >
    <template #actions>
      <EditActions
        v-if="editing"
        :changes="session.draft.value?.commands.length ?? 0"
        :busy="session.busy.value"
        @add="pane?.add()"
        @add-section="pane?.addSection()"
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
        :phone="small"
        @spacecraft="setQuery({ spacecraft: $event })"
        @range="onRange"
        @refresh="setQuery({ refresh: $event === '2s' ? null : $event })"
        @edit="setQuery({ edit: '1' })"
        @menu="onMenu"
      />
    </template>
    <template v-if="!small" #clocks><CockpitStatus /></template>
    <!-- Phone (ux Dashboards.md §Phone): row 2 is scope and range; they decide every plot. -->
    <template v-if="small && !editing" #subrow>
      <ViewerControls
        phone
        :scope-options="view?.scope_options ?? []"
        :spacecraft="runtime.spacecraftId"
        :selection="selection"
        :refresh="refresh"
        @spacecraft="setQuery({ spacecraft: $event })"
        @range="onRange"
      />
    </template>
  </TakeoverHeader>
  <ApCallout v-if="connection === 'offline'" tone="stale">
    Live connection lost. Values may be out of date; they'll refresh when it's back.
  </ApCallout>
  <ApCallout v-else-if="live.stalled.value && !editing" tone="stale">
    Live updates aren't arriving for this dashboard. Values may be out of date.
  </ApCallout>
  <ApCallout v-if="sourceNote && !editing" tone="caution">
    {{ sourceNote }}
    <template #action>
      <ApButton size="compact" variant="secondary" @click="sourceNote = null">Dismiss</ApButton>
    </template>
  </ApCallout>
  <EditorPane
    v-if="editing && view"
    ref="pane"
    :session="session"
    :view="view"
    :mission-id="missionId"
    @saved="onSaved"
  />
  <ViewerBody v-else :state="shown" :stale="connection === 'offline'" @retry="query.refetch" />
  <!-- Phone: health stays on screen in a bottom bar (ux 45d26151f); kiosk has its own line. -->
  <template v-if="small && !kiosk">
    <div aria-hidden="true" class="h-[calc(48px+env(safe-area-inset-bottom))] flex-none" />
    <PhoneStatusBar />
  </template>
  <VersionsSheet
    ref="versions"
    :mission-id="missionId"
    :dashboard-id="dashboardId"
    :can-restore="canEdit && !editing"
    @restored="onRestored"
  />
  <SnapshotSheet
    ref="snapshotSheet"
    :mission-id="missionId"
    :dashboard-id="dashboardId"
    :selection="selection"
    :spacecraft-id="runtime.spacecraftId"
    :version="currentVersion"
  />
  <CopySheet
    ref="copySheet"
    :mission-id="missionId"
    :dashboard-id="dashboardId"
    :name="view?.dashboard.name ?? 'Dashboard'"
    @copied="session.discard"
  />
</template>
