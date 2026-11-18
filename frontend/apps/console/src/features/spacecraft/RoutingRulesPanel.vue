<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useConfigState } from "@/features/changes/index.ts";
import { ApButton, ApEmptyState, ApPanel, ApTable, ApTag, type ApColumn } from "@/ui";
import OlderRouteRemove from "./OlderRouteRemove.vue";
import RemoveRouteSheet from "./RemoveRouteSheet.vue";
import { directionLabel, type RoutingRule } from "./detail.ts";
import { stagedRemovals } from "./older-route.ts";
import { actionRows, routeTag, stationWord } from "./routes.ts";

/**
 * D4 Routing for this spacecraft. U79: each route says where it comes from, `Add extra route` sits
 * above the list, and the spacecraft's own routes have Edit and Remove…, both staged.
 */
const props = defineProps<{
  missionId: MissionId;
  spacecraftName: string;
  rules: readonly RoutingRule[];
  /** Stage into the change set (the spacecraft page's gate). */
  canStage: boolean;
}>();
const active = computed(() => props.rules.filter((r) => r.active));
const routeOf = computed(() => actionRows(active.value));
const remover = ref<InstanceType<typeof RemoveRouteSheet> | null>(null);
/** ux U79: an older route whose removal is in the open set (inferred from it, per api/lead). */
const config = useConfigState(props.missionId);
const removals = computed(() =>
  config.state.value.status === "ready"
    ? stagedRemovals(config.state.value.value.change_set)
    : null,
);
const columns = computed((): readonly ApColumn[] => [
  { key: "name", label: "Rule" },
  { key: "source", label: "Source" },
  { key: "direction", label: "Direction" },
  { key: "role", label: "Role" },
  { key: "transport", label: "Transport" },
  { key: "state", label: "State" },
  ...(props.canStage ? [{ key: "actions", label: "", align: "end" as const }] : []),
]);
function remove(rule: RoutingRule) {
  const routeId = routeOf.value.get(rule.id);
  if (routeId)
    remover.value?.open({ routeId, name: rule.name, station: stationWord(rule.station) });
}
</script>

<template>
  <ApPanel index="D4" title="Routing" flush>
    <template #meta>
      {{ active.length }} active ·
      <RouterLink
        :to="{ name: 'setup.comms' }"
        class="text-readout no-underline hover:text-bright max-md:hit-44"
        >Comms &amp; routing →</RouterLink
      >
    </template>
    <div v-if="canStage" class="flex justify-end border-b border-hairline px-4 py-2.5">
      <ApButton size="compact" :to="{ query: { route: 'new' } }">Add extra route</ApButton>
    </div>
    <ApEmptyState
      v-if="active.length === 0"
      state="off"
      headline="No routing rule"
      sentence="It can't be contacted until a routing rule covers it."
    />
    <ApTable
      v-else
      :columns="columns"
      :rows="active"
      :row-key="(r) => r.id"
      caption="Routing rules"
    >
      <template #cell-name="{ row }">
        {{ row.name }}<span v-if="row.purpose" class="text-text-4"> · {{ row.purpose }}</span>
        <span v-if="routeTag(row)?.note" class="block text-sm text-text-3">{{
          routeTag(row)?.note
        }}</span>
        <!-- ux A6: why there's no Edit, as reachable text (not a disabled button). -->
        <span
          v-if="canStage && routeTag(row)?.reason"
          tabindex="0"
          class="block text-sm text-text-3"
          >{{ routeTag(row)?.reason }}</span
        >
      </template>
      <template #cell-source="{ row }">
        <ApTag v-if="routeTag(row)" :label="routeTag(row)?.label" />
      </template>
      <template #cell-direction="{ row }">{{ directionLabel(row.direction) }}</template>
      <template #cell-role="{ row }"
        ><span class="capitalize">{{ row.role }}</span></template
      >
      <template #cell-transport="{ row }">{{ row.transport.name }}</template>
      <template #cell-state="{ row }">
        <span :class="row.enabled ? 'text-text-3' : 'text-caution-text'">{{
          row.enabled ? "Enabled" : "Disabled"
        }}</span>
      </template>
      <template #cell-actions="{ row }">
        <span v-if="routeOf.has(row.id)" class="flex items-center justify-end gap-2">
          <ApButton size="compact" :to="{ query: { route: routeOf.get(row.id) } }">Edit</ApButton>
          <ApButton size="compact" variant="ghost" @click="remove(row)">Remove…</ApButton>
        </span>
        <OlderRouteRemove
          v-else-if="row.origin === 'legacy'"
          :mission-id="missionId"
          :rule="row"
          :spacecraft-name="spacecraftName"
          :staged="removals?.has(row.id) ?? false"
        />
      </template>
    </ApTable>
    <RemoveRouteSheet ref="remover" :mission-id="missionId" :spacecraft-name="spacecraftName" />
  </ApPanel>
</template>
