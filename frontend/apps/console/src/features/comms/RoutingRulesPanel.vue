<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import {
  ApCallout,
  ApEmptyState,
  ApPanel,
  ApRemote,
  ApTable,
  formatCount,
  plural,
  type ApColumn,
} from "@/ui";
import RoutingGroupRules from "./RoutingGroupRules.vue";
import { directionLabel, fetchRoutingGroups, groupKey } from "./api.ts";

/**
 * Routing rules as groups (pass-2 #10): a thousand per-spacecraft rules read as one line per
 * transport, direction and role. The transport links to that group's rules. Read-only; this view
 * is rebuilt around profile rules (DECISIONS #3).
 */
const route = useRoute();
const scope = useMissionScope();
const { state, refetch } = useRemoteQuery(() => scope.value.mission.id, fetchRoutingGroups);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const selectedKey = computed(() =>
  typeof route.query.group === "string" ? route.query.group : null,
);
const selected = computed(() =>
  state.value.status === "ready"
    ? (state.value.value.find((g) => groupKey(g) === selectedKey.value) ?? null)
    : null,
);
const total = computed(() =>
  state.value.status === "ready"
    ? state.value.value.reduce((n, g) => n + g.enabled_count + g.disabled_count, 0)
    : 0,
);
const columns: readonly ApColumn[] = [
  { key: "transport", label: "Transport" },
  { key: "direction", label: "Direction" },
  { key: "role", label: "Role" },
  { key: "spacecraft", label: "Spacecraft", align: "end", mono: true },
  { key: "rules", label: "Rules", align: "end", mono: true },
];
</script>

<template>
  <ApPanel
    index="T2"
    title="Routing rules"
    :meta="
      state.status === 'ready'
        ? `${plural(state.value.length, 'group')} · ${formatCount(total)} rules`
        : undefined
    "
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
        <ApEmptyState
          v-if="value.length === 0"
          state="off"
          headline="No routing rules"
          sentence="A rule routes a spacecraft's traffic over a transport."
        />
        <ApTable
          v-else
          :columns="columns"
          :rows="value"
          :row-key="groupKey"
          caption="Routing rule groups"
        >
          <template #cell-transport="{ row }">
            <RouterLink
              :to="{ name: 'setup.comms', query: { group: groupKey(row) } }"
              :aria-current="groupKey(row) === selectedKey ? 'true' : undefined"
              class="text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
              :class="groupKey(row) === selectedKey ? 'font-semibold text-bright' : ''"
              >{{ row.transport.name }}</RouterLink
            >
          </template>
          <template #cell-direction="{ row }">{{ directionLabel(row.direction) }}</template>
          <template #cell-role="{ row }"
            ><span class="capitalize">{{ row.role }}</span></template
          >
          <template #cell-spacecraft="{ row }">{{ formatCount(row.spacecraft_count) }}</template>
          <template #cell-rules="{ row }"
            >{{ formatCount(row.enabled_count)
            }}<span v-if="row.disabled_count > 0" class="text-caution-text">
              · {{ formatCount(row.disabled_count) }} disabled</span
            ></template
          >
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
  <RoutingGroupRules v-if="selected" :key="groupKey(selected)" :group="selected" />
</template>
