<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue";
import { useRoute } from "vue-router";
import { useMissionScope, useSmallScreen } from "@/shell/index.ts";
import {
  useNow,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApSheet,
  ApTabLinks,
} from "@/ui";
import { contactsSections } from "../sections.ts";
import { useSelectedPass } from "../useSelectedPass.ts";
import type { Pass } from "../api.ts";
import { HAND_STARTED_LISTED, stepWeek } from "./history.ts";
import { useHistory } from "./useHistory.ts";
import { useHistoryLookups } from "./useHistoryLookups.ts";
import HistoryWeekNav from "./HistoryWeekNav.vue";
import HistoryFilters from "./HistoryFilters.vue";
import HistoryTable from "./HistoryTable.vue";
import HistoryDrawer from "./HistoryDrawer.vue";
import {
  announceText,
  countMeta,
  drawerTitle,
  emptyText,
  rowCounts,
  shortDayCallout,
  stationName,
} from "./words.ts";

/**
 * Contacts › History (§11c(C) A12, ux U78): passes whose window has started, a week at a time,
 * newest first. A row opens the drawer on `?contact=`: an aside from 1100px, else a sheet (§9).
 */
const scope = useMissionScope();
const route = useRoute();
const now = useNow();
const missionId = computed(() => scope.value.mission.id);
const h = useHistory(missionId, now);
const look = useHistoryLookups(missionId, h.query);

/** U78 widths: the id columns and the aside from 1100 (the console breakpoint). */
const small = useSmallScreen();
const wideQuery =
  typeof window.matchMedia === "function" ? window.matchMedia("(min-width: 68.75rem)") : null;
const wide = ref(wideQuery?.matches ?? true);
const onWide = (e: MediaQueryListEvent) => (wide.value = e.matches);
wideQuery?.addEventListener("change", onWide);
onBeforeUnmount(() => wideQuery?.removeEventListener("change", onWide));
const width = computed(() => (small.value ? "phone" : wide.value ? "wide" : "mid"));

/** The drawer shows only what the URL names: History has no 'next AOS' default (fe-ops). */
const selectedId = computed(() => h.query.value.contact);
const noDefault = computed<readonly Pass[]>(() => []);
const pick = useSelectedPass(missionId, h.passes, noDefault, selectedId, look.byId, now);
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const shownRow = computed(() => pick.selected.value ?? pick.handStarted.value);
// A row named by another id (a Timeline link) keys on its own id and shows its week.
watch(shownRow, (r) => {
  if (!r) return;
  if (r.id !== selectedId.value) void h.go({ contact: r.id });
  else if (route.query.week === undefined && !h.rows.value.some((x) => x.id === r.id)) {
    void h.go({ week: h.weekOf(r) });
  }
});
watch(
  [selectedId, wide],
  ([id, w]) => {
    if (id !== null && !w) sheet.value?.open();
  },
  { flush: "post" },
);

const ready = computed(() => h.ledger.state.value.status === "ready");
const short = computed(() => h.shortDays.value.length > 0);
const counts = computed(() => (ready.value ? rowCounts(h.rows.value) : null));
const meta = computed(() =>
  counts.value ? countMeta(counts.value.passes, short.value) : undefined,
);
const announce = computed(() =>
  counts.value ? announceText(h.span.value, now.value.getTime(), counts.value, short.value) : "",
);
const filtered = computed(
  () =>
    h.query.value.spacecraftId !== null ||
    h.query.value.station !== null ||
    h.query.value.states.length > 0,
);
const older = computed(() => stepWeek(h.query.value.week, -1, now.value.getTime()) ?? undefined);
const sheetTitle = computed(() => {
  const hs = pick.handStarted.value;
  if (hs) return drawerTitle("record", look.spacecraftName(hs), null);
  const p = pick.selected.value;
  return drawerTitle("pass", p ? look.spacecraftName(p) : null, p ? stationName(p.station) : null);
});
const clear = () => h.go({ spacecraft: undefined, station: undefined, state: undefined });
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApPageHeader label="Ground network" title="Contacts">
      <p v-if="meta" class="m-0 font-mono text-sm text-text-3 uppercase">{{ meta }}</p>
    </ApPageHeader>
    <ApTabLinks :links="contactsSections" active="history" label="Contacts sections" />
    <HistoryWeekNav
      :week="h.query.value.week"
      :span="h.span.value"
      :now="now.getTime()"
      @week="(w) => h.go({ week: w })"
    />
    <HistoryFilters
      :query="h.query.value"
      :spacecraft="look.spacecraftOptions.value"
      :stations="look.stationOptions.value"
      :names="look.names.value"
      :counts="counts"
      :short="short"
      @filter="h.go"
    />
    <ApCallout v-for="d in h.shortDays.value" :key="d.day" tone="info">{{
      shortDayCallout(d)
    }}</ApCallout>
    <p role="status" class="sr-only">{{ announce }}</p>
    <div
      class="grid grid-cols-1 gap-3 console:min-h-0 console:flex-1"
      :class="wide && selectedId !== null ? 'console:grid-cols-[minmax(0,1fr)_360px]' : ''"
    >
      <ApPanel title="Contact history" pane flush>
        <p
          v-if="h.ledger.state.value.status === 'loading'"
          role="status"
          class="m-0 px-4 py-3 font-mono text-sm text-text-4"
        >
          LOADING…
        </p>
        <ApCallout v-else-if="h.ledger.state.value.status === 'failed'" tone="caution">
          Contact history couldn't load.
          <template #action
            ><ApButton size="compact" @click="h.ledger.refetch">Try again</ApButton></template
          >
        </ApCallout>
        <ApEmptyState
          v-else-if="h.items.value.length === 0"
          :headline="emptyText(h.span.value, now.getTime(), look.names.value)"
        >
          <ApButton v-if="filtered" size="compact" @click="clear">Clear filters</ApButton>
          <ApButton v-else size="compact" @click="h.go({ week: older })">‹ Older week</ApButton>
        </ApEmptyState>
        <HistoryTable
          v-else
          :items="h.items.value"
          :width="width"
          :selected-id="selectedId"
          :caption="`Contact history. ${announce}`"
          :spacecraft-name="look.spacecraftName"
        />
        <p v-if="!HAND_STARTED_LISTED" class="m-0 px-4 py-2 text-sm text-text-3">
          Booked passes only. Contacts started by hand show in
          <RouterLink
            :to="{ name: 'ops.timeline', query: { kind: 'contact' } }"
            class="text-readout"
            >Timeline</RouterLink
          >.
        </p>
      </ApPanel>
      <aside v-if="wide && selectedId !== null" class="flex min-h-0 flex-col">
        <HistoryDrawer
          :mission-id="missionId"
          :pass="pick.selected.value"
          :hand-started="pick.handStarted.value"
          :loading="pick.loading.value"
          :missing="pick.missing.value"
          :spacecraft="pick.spacecraft.value"
          @changed="pick.refetch"
        />
      </aside>
    </div>
    <ApSheet
      v-if="!wide"
      ref="sheet"
      :title="sheetTitle"
      placement="side"
      @closed="h.go({ contact: undefined })"
    >
      <HistoryDrawer
        :mission-id="missionId"
        :pass="pick.selected.value"
        :hand-started="pick.handStarted.value"
        :loading="pick.loading.value"
        :missing="pick.missing.value"
        :spacecraft="pick.spacecraft.value"
        @changed="pick.refetch"
      />
    </ApSheet>
  </div>
</template>
