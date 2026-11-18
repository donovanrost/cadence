<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import { ApPanel, ApRemote, ApTable, formatCount, type ApColumn } from "@/ui";
import { directionLabel, fetchRoutingRules, type RoutingGroup } from "./api.ts";

/** One routing group's rules: the transport's rules filtered to the group's direction and role. */
const props = defineProps<{ group: RoutingGroup }>();
const scope = useMissionScope();
const { state, refetch } = useRemoteQuery(
  () => ({ missionId: scope.value.mission.id, transportId: props.group.transport.id }),
  fetchRoutingRules,
);
const rules = computed(() =>
  state.value.status === "ready"
    ? state.value.value.rules.filter(
        (r) => r.direction === props.group.direction && r.role === props.group.role,
      )
    : [],
);
const columns: readonly ApColumn[] = [
  { key: "spacecraft", label: "Spacecraft" },
  { key: "rule", label: "Rule" },
];
</script>

<template>
  <ApPanel
    index="T2.1"
    :title="`${group.transport.name} · ${directionLabel(group.direction)} · ${group.role}`"
    flush
  >
    <template #meta
      ><RouterLink :to="{ name: 'setup.comms' }" class="text-text-3 hover:text-readout"
        >Close</RouterLink
      ></template
    >
    <ApRemote :state="state" loading-label="Loading rules…" @retry="refetch">
      <template #default="{ value }">
        <ApTable :columns="columns" :rows="rules" :row-key="(r) => r.id" caption="Group rules">
          <template #cell-spacecraft="{ row }">
            <RouterLink
              :to="{ name: 'setup.spacecraft.one', params: { spacecraftId: row.spacecraft.id } }"
              class="text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
              >{{ row.spacecraft.name ?? "Unknown spacecraft" }}</RouterLink
            >
          </template>
          <template #cell-rule="{ row }"
            >{{ row.display_name
            }}<span v-if="!row.enabled" class="text-caution-text"> · disabled</span></template
          >
          <template v-if="value.total > value.rules.length" #footer>
            <p class="m-0 border-t border-hairline px-4 py-2.5 text-sm text-text-3">
              Showing the first {{ formatCount(value.rules.length) }} of
              {{ formatCount(value.total) }} rules on this transport. Each spacecraft's rules are on
              its page.
            </p>
          </template>
        </ApTable>
      </template>
    </ApRemote>
  </ApPanel>
</template>
