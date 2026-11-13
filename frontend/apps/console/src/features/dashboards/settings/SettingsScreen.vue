<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApButton, ApPageHeader, ApRemote, ApTabLinks } from "@/ui";
import ActivityTab from "./ActivityTab.vue";
import { exportUrl, fetchSettings } from "./api.ts";
import DiagnosticsTab from "./DiagnosticsTab.vue";
import GeneralTab from "./GeneralTab.vue";
import SharingTab from "./SharingTab.vue";

/** Dashboard settings (ux Dashboards.md § Settings, slice 5): General · Sharing · Activity · Diagnostics. */
const route = useRoute();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const dashboardId = computed(() =>
  typeof route.params.dashboardId === "string" ? route.params.dashboardId : "",
);
const tabs = ["general", "sharing", "activity", "diagnostics"] as const;
type Tab = (typeof tabs)[number];
const tab = computed((): Tab => {
  const t = route.params.tab;
  return tabs.find((x) => x === t) ?? "general";
});
const key = computed(() => ({ missionId: missionId.value, dashboardId: dashboardId.value }));
const settings = useRemoteQuery(key, fetchSettings);
useMissionInvalidation(missionId, ["dashboards"], settings.refetch);
const name = computed(() =>
  settings.state.value.status === "ready" ? settings.state.value.value.dashboard.name : "Dashboard",
);
const to = (t: Tab) => ({
  name: "ops.dashboard.settings",
  params: { dashboardId: dashboardId.value, tab: t },
});
const links = tabs.map((t) => ({ key: t, label: t[0]?.toUpperCase() + t.slice(1), to: to(t) }));
const crumbs = computed(() => [
  { label: "Dashboards", to: { name: "ops.dashboards" } },
  { label: name.value, to: { name: "ops.dashboard", params: { dashboardId: dashboardId.value } } },
  { label: "Settings" },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1100px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader
      :label="`${scope.mission.name} · dashboard settings`"
      :title="name"
      size="reading"
    >
      <!-- ux § Export: downloads the bundle (JSON); the server records the export. -->
      <ApButton :href="exportUrl(key)" download>Export</ApButton>
    </ApPageHeader>
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
          @saved="settings.refetch"
        />
        <SharingTab v-else :settings-key="key" :settings="value" @changed="settings.refetch" />
      </template>
    </ApRemote>
  </div>
</template>
