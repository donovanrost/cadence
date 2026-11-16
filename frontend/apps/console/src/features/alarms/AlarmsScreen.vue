<script setup lang="ts">
import { computed, ref } from "vue";
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
import {
  ALARM_TABS,
  alarmRows,
  byPoint,
  groupAlarmRows,
  lastClearedLine,
  tabCounts,
  type AlarmTab,
  episodesCapNote,
} from "./list.ts";
import { useActiveEpisodes, useClearedEpisodes } from "./useAlarms.ts";

/**
 * Alarms (OpsLists.md §Alarms) on alarm episodes: "What's out of limits right now, and who has it?"
 * Tabs New · Acknowledged · Cleared (24 h) live in the URL (?tab=), the point filter too.
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
    : "new";
});
const active = useActiveEpisodes(missionId);
const cleared = useClearedEpisodes(
  missionId,
  // Also read when nothing is active: the empty state names the last clear.
  computed(
    () =>
      tab.value === "cleared" ||
      (active.state.value.status === "ready" && active.state.value.value.summary.active === 0),
  ),
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
  const fresh = s.value.episodes.filter((e) => e.status === "new").length;
  return `${plural(s.value.summary.active, "alarm")} active · ${fresh} new`;
});
const tabs = computed(() =>
  ALARM_TABS.map((key) => {
    const count = counts.value?.[key] ?? null;
    return {
      key,
      label: key === "cleared" ? "Cleared · 24 h" : key[0]?.toUpperCase() + key.slice(1),
      to: { query: { ...route.query, tab: key === "new" ? undefined : key } },
      ...(count === null ? {} : { count }),
    };
  }),
);
/** Expanded group headers (identical point + condition), by key. Grouping is off under a point filter. */
const expanded = ref<ReadonlySet<string>>(new Set());
function toggle(key: string) {
  const next = new Set(expanded.value);
  if (!next.delete(key)) next.add(key);
  expanded.value = next;
}
const rowsOf = (episodes: Parameters<typeof alarmRows>[0]) => {
  const rows = alarmRows(episodes, fleetRows.value, tab.value, point.value, now.value);
  return point.value === null ? groupAlarmRows(rows, expanded.value) : rows;
};
/** OpsLists §Alarms empty: "No active alarms. Last cleared 01:12Z on EARENDIL-047." */
const lastCleared = computed(() =>
  cleared.state.value.status === "ready"
    ? lastClearedLine(cleared.state.value.value.episodes, now.value)
    : null,
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
            <ApCallout
              v-if="tab === 'new' && point === null && value.summary.active === 0"
              tone="nominal"
            >
              No active alarms.{{ lastCleared ? ` ${lastCleared}` : "" }}
            </ApCallout>
            <ApEmptyState v-else-if="rowsOf(value.episodes).length === 0" :headline="empty" />
            <template v-else>
              <AlarmTable class="max-md:hidden" :rows="rowsOf(value.episodes)" @toggle="toggle" />
              <AlarmRowList class="md:hidden" :rows="rowsOf(value.episodes)" @toggle="toggle" />
              <p
                v-if="
                  episodesCapNote(
                    value.episodes.length,
                    tab === 'new' ? value.summary.active : null,
                  )
                "
                class="m-0 border-t border-hairline px-4 py-2 text-sm text-text-3"
              >
                {{
                  episodesCapNote(
                    value.episodes.length,
                    tab === "new" ? value.summary.active : null,
                  )
                }}
              </p>
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
