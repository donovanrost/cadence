<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { StagedArchive, type RefusalOutcome } from "@/features/changes/index.ts";
import { ApTable, ApTag, formatCount, type ApColumn } from "@/ui";
import { directionLabel, type Transport } from "./api.ts";

/**
 * T1's rows. ux U82: an active transport has 'Archive…' in its ⋯ menu (both origins, domain); an
 * archived one shows the 'ARCHIVED' tag, its name at full contrast, and no action but opening.
 */
const props = defineProps<{
  missionId: MissionId;
  rows: readonly Transport[];
  columns: readonly ApColumn[];
  canStage: boolean;
}>();
const emit = defineEmits<{ refused: [outcome: RefusalOutcome] }>();
const cols = (): readonly ApColumn[] =>
  props.canStage ? [...props.columns, { key: "actions", label: "", align: "end" }] : props.columns;
</script>

<template>
  <ApTable :columns="cols()" :rows="rows" :row-key="(t) => t.id" caption="Transports">
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'setup.comms.transports', params: { transportId: row.id } }"
        class="font-semibold text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
        >{{ row.display_name }}</RouterLink
      >
      <span class="font-mono text-xs text-text-4"> v{{ row.version }}</span>
      <ApTag v-if="row.lifecycle_state === 'archived'" label="ARCHIVED" class="ms-2" />
    </template>
    <template #cell-station="{ row }">{{ row.station?.display_name ?? "—" }}</template>
    <template #cell-direction="{ row }">{{ directionLabel(row.direction_capability) }}</template>
    <template #cell-origin="{ row }">{{
      row.origin === "direct" ? "Direct" : "Provider managed"
    }}</template>
    <template #cell-rules="{ row }">{{ formatCount(row.routing_rule_count) }}</template>
    <template #cell-actions="{ row }">
      <StagedArchive
        v-if="row.lifecycle_state === 'active'"
        :mission-id="missionId"
        kind="transport"
        :entity-id="row.id"
        :name="row.display_name"
        surface="transports"
        variant="menu"
        @refused="emit('refused', $event)"
      />
    </template>
  </ApTable>
</template>
