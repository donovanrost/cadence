<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import {
  ApCallout,
  ApEmptyState,
  ApPanel,
  ApRemote,
  ApTable,
  formatCount,
  type ApColumn,
} from "@/ui";
import { directionLabel, fetchRoutingRules } from "./api.ts";

/** Routing rules, read-only and minimal: this view is rebuilt around profile rules (DECISIONS #3). */
const scope = useMissionScope();
const { state, refetch } = useRemoteQuery(() => scope.value.mission.id, fetchRoutingRules);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const columns: readonly ApColumn[] = [
  { key: "spacecraft", label: "Spacecraft" },
  { key: "rule", label: "Rule" },
  { key: "direction", label: "Direction" },
  { key: "role", label: "Role" },
  { key: "transport", label: "Transport" },
];
</script>

<template>
  <ApPanel
    index="T2"
    title="Routing rules"
    :meta="state.status === 'ready' ? `${formatCount(state.value.total)} rules` : undefined"
    flush
  >
    <ApCallout tone="info">
      Rules are set per spacecraft today. They move onto the profile, one rule generating routes for
      every spacecraft, and this view is rebuilt around them.
    </ApCallout>
    <ApEmptyState
      v-if="notProvided"
      state="off"
      headline="Routing rules not available in the console yet"
    />
    <ApRemote v-else :state="state" loading-label="Loading routing rules…" @retry="refetch">
      <template #default="{ value }">
        <ApTable
          :columns="columns"
          :rows="value.rules"
          :row-key="(r) => r.id"
          caption="Routing rules"
        >
          <template #cell-spacecraft="{ row }">
            <RouterLink
              :to="{ name: 'setup.spacecraft.one', params: { scId: row.spacecraft.id } }"
              class="text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
              >{{ row.spacecraft.name }}</RouterLink
            >
          </template>
          <template #cell-rule="{ row }"
            >{{ row.display_name
            }}<span v-if="!row.enabled" class="text-caution-text"> · disabled</span></template
          >
          <template #cell-direction="{ row }">{{ directionLabel(row.direction) }}</template>
          <template #cell-role="{ row }"
            ><span class="capitalize">{{ row.role }}</span></template
          >
          <template #cell-transport="{ row }">{{ row.transport.display_name }}</template>
          <template v-if="value.total > value.rules.length" #footer>
            <p class="m-0 border-t border-hairline px-4 py-2.5 text-sm text-text-3">
              Showing {{ formatCount(value.rules.length) }} of {{ formatCount(value.total) }}. Each
              spacecraft's rules are on its page.
            </p>
          </template>
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
</template>
