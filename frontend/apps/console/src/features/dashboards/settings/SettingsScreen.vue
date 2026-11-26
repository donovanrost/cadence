<script setup lang="ts">
import { computed, watch } from "vue";
import { useRoute, useRouter, type RouteLocationRaw } from "vue-router";
import { useRemoteQuery, dashboardIdSegment } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import {
  ApBreadcrumb,
  ApButton,
  ApPageHeader,
  ApRemote,
  ApTabLinks,
  type ApCrumb,
  type ApTabLink,
} from "@/ui";
import { fetchDashboard } from "../api.ts";
import ActivityTab from "./ActivityTab.vue";
import { exportUrl, fetchSettings } from "./api.ts";
import DiagnosticsTab from "./DiagnosticsTab.vue";
import GeneralTab from "./GeneralTab.vue";
import SharingTab from "./SharingTab.vue";
import { settingsTabs, type SettingsTab } from "./present.ts";

/**
 * Dashboard settings (ux Dashboards.md § Settings, slice 5). Authors: General · Sharing · Activity ·
 * Diagnostics. Everyone else (dashboards, L8b parity with the legacy pages): Activity · Diagnostics,
 * General and Sharing hidden. Who's an author comes from the viewer's D5 `can_edit`, so the page
 * never depends on D14, which only authors may read.
 */
const route = useRoute("ops.dashboard.settings");
const router = useRouter();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const dashboardId = computed(() => dashboardIdSegment(route.params.dashboardId));
const key = computed(() => ({ missionId: missionId.value, dashboardId: dashboardId.value }));
const head = useRemoteQuery(key, (k, signal) =>
  fetchDashboard(k.missionId, k.dashboardId, { from: "", to: "", spacecraftId: "" }, signal),
);
const view = computed(() => (head.state.value.status === "ready" ? head.state.value.value : null));
const author = computed(() => view.value?.can_edit === true);
const tabs = computed(() => settingsTabs(author.value));
const tab = computed(
  (): SettingsTab => tabs.value.find((t) => t === route.params.tab) ?? tabs.value[0] ?? "activity",
);
// A member's General or Sharing link lands on Activity, not an error.
watch([view, tab], ([v, t]) => {
  if (v && route.params.tab !== undefined && route.params.tab !== t) void router.replace(to(t));
});
const settings = useRemoteQuery(
  computed(() => (author.value ? key.value : null)),
  fetchSettings,
);
useMissionInvalidation(missionId, ["dashboards"], () => {
  head.refetch();
  settings.refetch();
});
const name = computed(() => view.value?.dashboard.name ?? "Dashboard");
const to = (t: SettingsTab): RouteLocationRaw => ({
  name: "ops.dashboard.settings",
  params: { dashboardId: dashboardId.value, tab: t },
});
const links = computed((): readonly ApTabLink[] =>
  tabs.value.map((t) => ({ key: t, label: t[0]?.toUpperCase() + t.slice(1), to: to(t) })),
);
const crumbs = computed((): readonly ApCrumb[] => [
  { label: "Dashboards", to: { name: "ops.dashboards" } },
  { label: name.value, to: { name: "ops.dashboard", params: { dashboardId: dashboardId.value } } },
  { label: author.value ? "Settings" : "Activity and diagnostics" },
]);
function onSaved() {
  settings.refetch();
  head.refetch();
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1100px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader
      :label="`${scope.mission.name} · ${author ? 'dashboard settings' : 'dashboard activity'}`"
      :title="name"
      size="reading"
    >
      <!-- ux § Export: downloads the bundle (JSON); D19 is author-only, and the server records it. -->
      <ApButton v-if="author" :href="exportUrl(key)" download>Export</ApButton>
    </ApPageHeader>
    <ApRemote :state="head.state.value" loading-label="Loading dashboard…" @retry="head.refetch">
      <ApTabLinks :links="links" :active="tab" label="Settings sections" />
      <ActivityTab v-if="tab === 'activity'" :settings-key="key" />
      <DiagnosticsTab v-else-if="tab === 'diagnostics'" :settings-key="key" />
      <ApRemote
        v-else
        :state="settings.state.value"
        loading-label="Loading settings…"
        @retry="settings.refetch"
      >
        <template #default="{ value }">
          <GeneralTab
            v-if="tab === 'general'"
            :settings-key="key"
            :settings="value"
            @saved="onSaved"
          />
          <SharingTab v-else :settings-key="key" :settings="value" @changed="settings.refetch" />
        </template>
      </ApRemote>
    </ApRemote>
  </div>
</template>
