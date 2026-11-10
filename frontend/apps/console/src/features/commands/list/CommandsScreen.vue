<script setup lang="ts">
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
import CommandTable from "./CommandTable.vue";
import { COMMAND_TABS, TAB_LABELS, tabCounts, tabFromQuery, tabRows } from "./list.ts";

/** Commands (IA rail 04): requests grouped by state; `?awaiting=me` is the GO-poll entry. */
const scope = useMissionScope();
const route = useRoute();
const access = useCommandAccess();
const missionId = computed(() => scope.value.mission.id);
const groups = useRemoteQuery(missionId, (m, signal) => fetchGroups(m, {}, signal));
const codeOf = useStationCodes(missionId);
useMissionInvalidation(
  computed<string | null>(() => missionId.value),
  ["commanding"],
  groups.refetch,
);
const nameOf = usePeopleNames();

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
const EMPTY: Record<string, string> = {
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
      <ApRemote
        :state="groups.state.value"
        loading-label="LOADING REQUESTS…"
        @retry="groups.refetch"
      >
        <template #default="{ value }">
          <ApEmptyState v-if="tabRows(value, tab).length === 0" :headline="EMPTY[tab] ?? ''" />
          <CommandTable v-else :rows="tabRows(value, tab)" :name-of="nameOf" :code-of="codeOf" />
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
