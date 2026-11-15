<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApTabLinks } from "@/ui";
import { useCommandAccess } from "../access.ts";
import { fetchGroups } from "../groups/api.ts";
import { usePeopleNames } from "../groups/usePeopleNames.ts";
import { useStationCodes } from "@/features/contacts/useStationCodes.ts";
import { fetchComposeDraft } from "../compose/saved.ts";
import { savedWhen } from "../compose/useComposeDraft.ts";
import CommandTable from "./CommandTable.vue";
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
const groups = useRemoteQuery(missionId, (m, signal) => fetchGroups(m, {}, signal));
const stations = useStationCodes(missionId);
useMissionInvalidation(
  computed<MissionId | null>(() => missionId.value),
  ["commanding"],
  groups.refetch,
);
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
  groups.state.value.status === "ready" ? tabCounts(groups.state.value.value) : null,
);
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
    <ApTabLinks :links="tabs" :active="tab" label="Request state" />
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
      <ApRemote
        :state="groups.state.value"
        loading-label="LOADING REQUESTS…"
        @retry="groups.refetch"
      >
        <template #default="{ value }">
          <ApEmptyState v-if="tabRows(value, tab).length === 0" :headline="EMPTY[tab]" />
          <CommandTable v-else :rows="tabRows(value, tab)" :name-of="nameOf" :stations="stations" />
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
