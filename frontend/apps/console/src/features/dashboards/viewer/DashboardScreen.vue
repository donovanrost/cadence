<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter, type LocationQueryValue } from "vue-router";
import { TakeoverHeader, useMissionScope } from "@/shell";
import { useConnection } from "@/live";
import { ApCallout, ApEmptyState, ApRemote } from "@/ui";
import type { Runtime } from "../api.ts";
import { selectionFromQuery, selectionParams, type TimeSelection } from "../model/time-range.ts";
import DashboardGrid from "./DashboardGrid.vue";
import InspectSheet from "./InspectSheet.vue";
import ViewerControls from "./ViewerControls.vue";
import CockpitStatus from "./CockpitStatus.vue";
import { refreshChoices, useDashboardView, type RefreshChoice } from "./useDashboardView.ts";

/**
 * Dashboard viewer (ux Dashboards.md): a takeover cockpit. The URL owns the runtime (`from`,
 * `to`, `spacecraft`, `refresh`); D5 resolves it; live step 1 refreshes on invalidations.
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
const query = useDashboardView(missionId, dashboardId, runtime, {
  refreshMs: computed(() => refreshChoices.find((c) => c.value === refresh.value)?.ms ?? null),
  sliding: computed(() => selection.value.kind !== "absolute"),
  paused: ref(false),
});
const view = computed(() =>
  query.state.value.status === "ready" ? query.state.value.value : null,
);
const connection = useConnection();
const inspect = ref<InstanceType<typeof InspectSheet> | null>(null);

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
  <TakeoverHeader
    :title="view?.dashboard.name ?? 'Dashboard'"
    context="DASHBOARD"
    :close="{ name: 'ops.dashboards' }"
    close-label="Close dashboard"
    title-as="h1"
  >
    <template #actions>
      <ViewerControls
        :scope-options="view?.scope_options ?? []"
        :spacecraft="runtime.spacecraftId"
        :selection="selection"
        :refresh="refresh"
        @spacecraft="setQuery({ spacecraft: $event })"
        @range="onRange"
        @refresh="setQuery({ refresh: $event === '2s' ? null : $event })"
      />
    </template>
    <template #clocks><CockpitStatus /></template>
  </TakeoverHeader>
  <ApCallout v-if="connection !== 'live'" tone="stale">
    Live connection lost. Values may be out of date; they'll refresh when it's back.
  </ApCallout>
  <ApRemote :state="query.state.value" @retry="query.refetch">
    <template #default="{ value }">
      <ApEmptyState
        v-if="value.snapshot === null"
        headline="This dashboard has no saved version yet."
        sentence="Its author needs to save it before others can view it."
        state="off"
      />
      <ApCallout v-else-if="value.snapshot.placements.length === 0" tone="info">
        This dashboard has no widgets yet.
      </ApCallout>
      <DashboardGrid
        v-else
        :class="{ 'opacity-60': connection !== 'live' }"
        :snapshot="value.snapshot"
        @inspect="inspect?.open($event)"
      />
    </template>
  </ApRemote>
  <InspectSheet ref="inspect" />
</template>
