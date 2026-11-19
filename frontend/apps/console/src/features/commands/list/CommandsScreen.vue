<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import { useRoute, useRouter, type LocationQuery } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApTabLinks } from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import { useCommandAccess } from "../access.ts";
import CommandFilters from "./CommandFilters.vue";
import { emptyLine, filtered, filtersOf, resultLine, withFilter } from "./filters.ts";
import { useGroupPages } from "./useGroupPages.ts";
import { usePeopleNames } from "../groups/usePeopleNames.ts";
import { useStationCodes } from "@/features/contacts/useStationCodes.ts";
import { fetchComposeDraft } from "../compose/saved.ts";
import { savedWhen } from "../compose/useComposeDraft.ts";
import CommandTable from "./CommandTable.vue";
import type { GroupRow } from "../groups/api.ts";
import {
  COMMAND_TABS,
  TAB_LABELS,
  tabCounts,
  tabFromQuery,
  tabRows,
  type CommandTab,
} from "./list.ts";

/** Commands (IA rail 04): requests grouped by state; `?awaiting=me` is the GO-poll entry. */
const scope = useMissionScope();
const route = useRoute();
const access = useCommandAccess();
const missionId = computed(() => scope.value.mission.id);
const router = useRouter();
/** ux U72: search, target and state go to the server; the pages follow its cursor. */
const filters = computed(() => filtersOf(route.query));
const isFiltered = computed(() => filtered(filters.value));
const groups = useGroupPages(missionId, filters);
const rows = computed(() =>
  groups.state.value.status === "ready" ? groups.state.value.value.rows : [],
);
const go = (query: LocationQuery) =>
  router.replace({ query }).catch((e: unknown) => console.error("Navigation failed", e));
const setFilter = (key: "q" | "target" | "stage", value: string | null) =>
  go(withFilter(route.query, key, value));
function clearFilters() {
  const { q: _q, target: _t, stage: _s, ...rest } = route.query;
  return go(rest);
}
const fleet = useFleet(missionId, { live: false });
const spacecraft = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value.spacecraft : [],
);
const nameOfSc = (id: string) => spacecraft.value.find((s) => s.id === id)?.name ?? id;
/** ux U72: after Load more, focus goes to the first new row's link. */
const list = ref<HTMLElement | null>(null);
async function loadMore() {
  const id = await groups.more();
  if (!id) return;
  await nextTick();
  list.value?.querySelector<HTMLElement>(`a[href*="${CSS.escape(id)}"]`)?.focus();
}
const stations = useStationCodes(missionId);
const nameOf = usePeopleNames();
/** The author's Compose draft (ux 36cca988): `Your draft · saved 02:44Z · Resume`. */
const draftQuery = useRemoteQuery(
  computed(() => (access.value.request ? missionId.value : null)),
  (m, signal) => fetchComposeDraft(m, signal),
);
const savedDraft = computed(() =>
  draftQuery.state.value.status === "ready" ? draftQuery.state.value.value : null,
);

const tab = computed(() => tabFromQuery(route.query));
const counts = computed(() =>
  groups.state.value.status === "ready" && !isFiltered.value ? tabCounts(rows.value) : null,
);
/** Filtered: the server's order across every tab; else the tab's rows. */
const shownRows = (all: readonly GroupRow[]) =>
  isFiltered.value ? [...all] : tabRows(all, tab.value);
const tabs = computed(() =>
  COMMAND_TABS.map((key) => {
    const { awaiting: _a, tab: _t, ...rest } = route.query;
    const count = counts.value?.[key] ?? null;
    return {
      key,
      label: TAB_LABELS[key],
      to: {
        query:
          key === "awaiting"
            ? { ...rest, awaiting: "me" }
            : key === "pending"
              ? rest
              : { ...rest, tab: key },
      },
      ...(count === null ? {} : { count }),
    };
  }),
);
const headline = computed(() => {
  const n = counts.value;
  if (!n) return "Commands";
  if (n.awaiting) return `${n.awaiting} await your GO`;
  return n.pending ? `${n.pending} waiting for a GO` : "No requests waiting";
});
const EMPTY: Readonly<Record<CommandTab, string>> = {
  awaiting: "Nothing awaits your GO.",
  pending: "No requests are waiting for a GO.",
  queued: "No released requests.",
  closed: "Nothing closed yet.",
};
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApPageHeader :label="`${scope.mission.name} · commands`" :title="headline">
      <ApButton v-if="access.request" size="compact" :to="{ name: 'ops.commands.new' }"
        >New command request</ApButton
      >
    </ApPageHeader>
    <CommandFilters
      :filters="filters"
      :spacecraft="spacecraft"
      @q="(q) => setFilter('q', q)"
      @target="(id) => setFilter('target', id)"
      @stages="(st) => setFilter('stage', st.join(',') || null)"
      @clear="clearFilters"
    />
    <!-- ux U69 A5a / U72: while filtered, the tabs give way to one line naming the result. -->
    <p
      v-if="isFiltered && groups.state.value.status === 'ready'"
      class="m-0 font-mono text-sm text-text-2"
      aria-live="polite"
    >
      {{ resultLine(filters, rows.length, groups.state.value.value.next !== null, nameOfSc) }}
    </p>
    <ApTabLinks v-else-if="!isFiltered" :links="tabs" :active="tab" label="Request state" />
    <ApPanel index="L1" title="Requests" pane flush>
      <div
        v-if="savedDraft"
        class="flex items-center justify-between gap-3 border-b border-hairline px-4 py-2.5"
      >
        <span class="font-mono text-sm text-readout"
          >Your draft · saved {{ savedWhen(savedDraft.saved_at) }}</span
        >
        <ApButton size="compact" :to="{ name: 'ops.commands.new', query: { draft: 'resume' } }"
          >Resume</ApButton
        >
      </div>
      <ApRemote :state="groups.state.value" loading-label="LOADING REQUESTS…" @retry="groups.retry">
        <template #default="{ value }">
          <ApEmptyState
            v-if="isFiltered && value.rows.length === 0"
            :headline="emptyLine(filters, nameOfSc)"
          >
            <ApButton size="compact" @click="clearFilters">Clear filters</ApButton>
          </ApEmptyState>
          <ApEmptyState v-else-if="shownRows(value.rows).length === 0" :headline="EMPTY[tab]" />
          <div v-else ref="list">
            <CommandTable :rows="shownRows(value.rows)" :name-of="nameOf" :stations="stations" />
          </div>
          <!-- ux U72: only while there's a next page; it disappears at the end. -->
          <div v-if="value.next" class="flex flex-col gap-1 border-t border-hairline px-4 py-2">
            <ApButton
              size="compact"
              variant="secondary"
              class="self-start"
              :disabled="groups.busy.value"
              disabled-reason="Loading…"
              @click="loadMore"
              >Load more</ApButton
            >
            <!-- a11y B6 (#243): a failed Load more is an alert. -->
            <p v-if="groups.moreError.value" role="alert" class="m-0 text-sm text-caution-text">
              {{ groups.moreError.value }}
            </p>
          </div>
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
