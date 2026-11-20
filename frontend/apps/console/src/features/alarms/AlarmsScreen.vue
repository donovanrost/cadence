<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import { RouterLink, useRoute, useRouter, type RouteLocationRaw } from "vue-router";
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
  lastChangeLine,
  lastClearedLine,
  tabCounts,
  type AlarmTab,
} from "./list.ts";
import { useActiveEpisodes, useClearedEpisodes } from "./useAlarms.ts";
import AlarmFilters from "./AlarmFilters.vue";
import { filtered, filteredEmpty, matches, shownLine, spacecraftOptions } from "./filters.ts";
import { useAlarmFilters } from "./useAlarmFilters.ts";

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
/** ux U69 A6: spacecraft + severity, in the URL, applied to the one read (counts need it all). */
const { filters, setFilter, clearFilters } = useAlarmFilters();
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
type Episodes = Parameters<typeof alarmRows>[0];
/** The tab's rows under the point filter, before the filter row. */
const tabRows = (episodes: Episodes) =>
  alarmRows(episodes, fleetRows.value, tab.value, point.value, now.value);
const rowsOf = (episodes: Episodes) => {
  const rows = tabRows(episodes.filter((e) => matches(e, filters.value)));
  return point.value === null ? groupAlarmRows(rows, expanded.value) : rows;
};
/** U25 and #237: a craft's name for a sentence; one the fleet can't name is "an unknown spacecraft", never its id. */
const nameOf = (id: string) =>
  fleetRows.value.find((sc) => sc.id === id)?.name ?? "an unknown spacecraft";
/** Picker: spacecraft with alarms in this tab (severity applied), each with its count. */
const scOptions = (episodes: Episodes) =>
  spacecraftOptions(
    tabRows(episodes.filter((e) => matches(e, { ...filters.value, spacecraftId: null }))).map(
      (r) => r.episode,
    ),
    filters.value.spacecraftId,
    nameOf,
  );
const options = computed(() =>
  shown.value.status === "ready" ? scOptions(shown.value.value.episodes) : [],
);
const shownOf = (episodes: Episodes, more: boolean) =>
  shownLine(
    tabRows(episodes.filter((e) => matches(e, filters.value))).length,
    tabRows(episodes).length,
    episodes.length,
    more,
  );
/** ux U72: Load more appends the next page; focus goes to the first new row's link. */
const list = ref<HTMLElement | null>(null);
async function loadMore() {
  const before = list.value?.querySelectorAll("tbody tr").length ?? 0;
  await (tab.value === "cleared" ? cleared : active).more();
  await nextTick();
  list.value?.querySelectorAll("tbody tr")[before]?.querySelector<HTMLElement>("a")?.focus();
}
/** ux U69 A6: the header's newest change, mission-wide (filters don't change it). */
const lastChange = computed(() =>
  active.state.value.status === "ready"
    ? lastChangeLine(
        active.state.value.value.summary.latest_change,
        (id) => fleetRows.value.find((sc) => sc.id === id)?.name ?? null,
        now.value,
      )
    : null,
);
/** ux U71 A12: the sentence links to its episode in Investigate (needs the spacecraft's SCID). */
const lastChangeTo = computed<RouteLocationRaw | null>(() => {
  const s = active.state.value;
  const c = s.status === "ready" ? s.value.summary.latest_change : null;
  const sc = c?.spacecraft_id ? fleetRows.value.find((x) => x.id === c.spacecraft_id) : null;
  return c && sc
    ? {
        name: "ops.spacecraft",
        params: { scId: sc.scid, tab: "investigate" },
        query: { alarm: c.episode_id },
      }
    : null;
});
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
    <ApPageHeader :label="`${scope.mission.name} · alarms`" :title="headline">
      <template v-if="lastChange" #subtitle>
        <RouterLink
          v-if="lastChangeTo"
          :to="lastChangeTo"
          class="font-mono text-sm text-text-3 hover:text-readout"
          >{{ lastChange }}</RouterLink
        >
        <span v-else class="font-mono text-sm text-text-3">{{ lastChange }}</span>
      </template>
    </ApPageHeader>
    <ApCallout v-if="limitsOff" tone="off">
      Ground limits aren't configured on this mission, so only live catalog alarms appear.
      <template #action
        ><ApButton size="compact" :to="{ name: 'setup.apps' }">Set up</ApButton></template
      >
    </ApCallout>
    <ApTabLinks :links="tabs" :active="tab" label="Alarm status" />
    <AlarmFilters
      :options="options"
      :spacecraft-id="filters.spacecraftId"
      :severities="filters.severities"
      @spacecraft="(id) => setFilter('sc', id)"
      @severities="(s) => setFilter('severity', s.join(',') || null)"
      @clear="clearFilters"
    />
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
              v-if="
                tab === 'new' && point === null && !filtered(filters) && value.summary.active === 0
              "
              tone="nominal"
            >
              No active alarms.{{ lastCleared ? ` ${lastCleared}` : "" }}
            </ApCallout>
            <ApEmptyState
              v-else-if="rowsOf(value.episodes).length === 0 && filtered(filters)"
              :headline="filteredEmpty(filters, nameOf)"
            >
              <ApButton size="compact" @click="clearFilters">Clear filters</ApButton>
            </ApEmptyState>
            <ApEmptyState v-else-if="rowsOf(value.episodes).length === 0" :headline="empty" />
            <template v-else>
              <p
                v-if="filtered(filters)"
                class="m-0 border-b border-hairline px-4 py-2 font-mono text-xs text-text-3 uppercase"
              >
                {{ shownOf(value.episodes, value.next !== null) }}
              </p>
              <div ref="list">
                <AlarmTable class="max-md:hidden" :rows="rowsOf(value.episodes)" @toggle="toggle" />
              </div>
              <AlarmRowList class="md:hidden" :rows="rowsOf(value.episodes)" @toggle="toggle" />
              <!-- ux U72: Load more only while there's a next page (A6d cursor). -->
              <div v-if="value.next" class="border-t border-hairline px-4 py-2">
                <ApButton
                  size="compact"
                  variant="secondary"
                  :disabled="(tab === 'cleared' ? cleared : active).busy.value"
                  disabled-reason="Loading…"
                  @click="loadMore"
                  >Load more</ApButton
                >
              </div>
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
