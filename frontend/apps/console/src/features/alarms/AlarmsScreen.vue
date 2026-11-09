<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import {
  plural,
  useNow,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTabLinks,
} from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import AlarmRowList from "./AlarmRowList.vue";
import AlarmTable from "./AlarmTable.vue";
import ByPointPanel from "./ByPointPanel.vue";
import { ALARM_TABS, alarmRows, byPoint, tabCounts, type AlarmTab } from "./list.ts";
import { useActiveEpisodes, useClearedEpisodes } from "./useAlarms.ts";

/**
 * Alarms (OpsLists.md §Alarms) on alarm episodes: "What's out of limits right now, and who has it?"
 * Tabs Active · Acknowledged · Cleared (24 h) live in the URL (?tab=), the point filter too.
 */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);
const fleet = useFleet(missionId);

const tab = computed<AlarmTab>(() => {
  const t = route.query.tab;
  return typeof t === "string" && (ALARM_TABS as readonly string[]).includes(t)
    ? (t as AlarmTab)
    : "active";
});
const active = useActiveEpisodes(missionId);
const cleared = useClearedEpisodes(
  missionId,
  computed(() => tab.value === "cleared"),
);
const shown = computed(() => (tab.value === "cleared" ? cleared.state.value : active.state.value));

const point = computed(() => (typeof route.query.point === "string" ? route.query.point : null));
function selectPoint(pointId: string | null) {
  const { point: _drop, ...rest } = route.query;
  router
    .replace({ query: pointId === null ? rest : { ...rest, point: pointId } })
    .catch((e: unknown) => console.error("Navigation failed", e));
}

const fleetRows = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
);
const limitsOff = computed(
  () => fleet.state.value.status === "ready" && !fleet.state.value.value.limits.configured,
);
const counts = computed(() =>
  active.state.value.status === "ready"
    ? tabCounts(
        active.state.value.value.episodes,
        cleared.state.value.status === "ready" ? cleared.state.value.value.episodes : null,
        now.value,
      )
    : null,
);
const headline = computed(() => {
  const s = active.state.value;
  if (s.status !== "ready") return "Alarms";
  if (s.value.summary.active === 0)
    return limitsOff.value ? "Ground limits off" : "No active alarms";
  return `${plural(s.value.summary.active, "alarm")} active`;
});
const tabs = computed(() =>
  ALARM_TABS.map((key) => {
    const count = counts.value?.[key] ?? null;
    return {
      key,
      label: key === "cleared" ? "Cleared · 24 h" : key[0]?.toUpperCase() + key.slice(1),
      to: { query: { ...route.query, tab: key === "active" ? undefined : key } },
      ...(count === null ? {} : { count }),
    };
  }),
);
const empty = computed(() =>
  tab.value === "cleared"
    ? "Nothing cleared in the last 24 h."
    : tab.value === "acknowledged"
      ? "No acknowledged alarms."
      : "No unacknowledged alarms.",
);
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApPageHeader :label="`${scope.mission.name} · alarms`" :title="headline" />
    <ApCallout v-if="limitsOff" tone="off">
      Ground limits aren't configured on this mission, so only live catalog alarms appear.
      <template #action
        ><ApButton size="compact" :to="{ name: 'setup.apps' }">Set up</ApButton></template
      >
    </ApCallout>
    <ApTabLinks :links="tabs" :active="tab" label="Alarm status" />
    <div
      class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1 console:grid-cols-[minmax(0,1fr)_340px]"
    >
      <ApPanel
        index="L1"
        title="Alarm table"
        :meta="point ? `filtered: ${point}` : undefined"
        pane
        flush
      >
        <ApRemote
          :state="shown"
          loading-label="LOADING ALARMS…"
          @retry="tab === 'cleared' ? cleared.refetch() : active.refetch()"
        >
          <template #default="{ value }">
            <ApEmptyState
              v-if="alarmRows(value.episodes, fleetRows, tab, point, now).length === 0"
              :headline="empty"
            />
            <template v-else>
              <AlarmTable
                class="max-md:hidden"
                :rows="alarmRows(value.episodes, fleetRows, tab, point, now)"
              />
              <AlarmRowList
                class="md:hidden"
                :rows="alarmRows(value.episodes, fleetRows, tab, point, now)"
              />
            </template>
          </template>
        </ApRemote>
      </ApPanel>
      <ByPointPanel
        v-if="active.state.value.status === 'ready'"
        :points="byPoint(active.state.value.value.episodes)"
        :selected="point"
        @select="selectPoint"
      />
    </div>
  </div>
</template>
