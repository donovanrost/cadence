<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { StagedArchive, type RefusalOutcome } from "@/features/changes/index.ts";
import { ApStatusMark, ApTable, ApTag, formatCount, type ApColumn } from "@/ui";
import type { Station } from "./api.ts";
import { stationName } from "./names.ts";
import StationCodeCell from "./StationCodeCell.vue";

/** Ground stations; health is "not reported" until the server tracks it (never assumed ok). */
const props = defineProps<{
  missionId: MissionId;
  rows: readonly Station[];
  canEdit?: boolean;
  /** Stations whose suggested code is staged in the change set, and the one being staged. */
  staged?: ReadonlySet<string>;
  busy?: string | null;
}>();
defineEmits<{ confirm: [station: Station]; refused: [outcome: RefusalOutcome] }>();
// U10: a column the server can't fill is left out, not shown as a column of dashes.
const linked = props.rows.some((s) => s.transport_count !== null);
const coded = props.canEdit === true || props.rows.some((s) => s.code !== null);
const allColumns: readonly ApColumn[] = [
  { key: "name", label: "Station" },
  { key: "code", label: "Code", mono: true },
  { key: "provider", label: "Provider" },
  { key: "region", label: "Region" },
  { key: "transports", label: "Transports", mono: true, align: "end" },
  { key: "rules", label: "Routing rules", mono: true, align: "end" },
  { key: "health", label: "Health" },
];
const columns = [
  ...allColumns.filter(
    (c) => (linked || (c.key !== "transports" && c.key !== "rules")) && (coded || c.key !== "code"),
  ),
  // ux U82: Archive… in the row's ⋯ menu, for whoever can stage.
  ...(props.canEdit === true ? [{ key: "actions", label: "", align: "end" as const }] : []),
];
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(s) => s.id" caption="Ground stations">
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'setup.stations', params: { stationId: row.id } }"
        class="font-semibold text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
        >{{ row.display_name }}</RouterLink
      >
      <ApTag v-if="row.lifecycle_state === 'archived'" label="ARCHIVED" class="ms-2" />
    </template>
    <!-- U25: never invent identifiers; a suggestion is dimmed and only real once confirmed. -->
    <template #cell-code="{ row }">
      <template v-if="row.code">{{ row.code }}</template>
      <StationCodeCell
        v-else
        :station="row"
        :can-edit="canEdit === true"
        :staged="staged?.has(row.id) === true"
        :busy="busy === row.id"
        @confirm="$emit('confirm', row)"
      />
    </template>
    <template #cell-provider="{ row }">{{ row.provider ?? "—" }}</template>
    <template #cell-region="{ row }">{{ row.region ?? "—" }}</template>
    <template #cell-transports="{ row }">{{
      row.transport_count === null ? "—" : formatCount(row.transport_count)
    }}</template>
    <template #cell-rules="{ row }">{{
      row.routing_rule_count === null ? "—" : formatCount(row.routing_rule_count)
    }}</template>
    <template #cell-actions="{ row }">
      <StagedArchive
        v-if="row.lifecycle_state === 'active'"
        :mission-id="missionId"
        kind="ground_station"
        :entity-id="row.id"
        :name="stationName(row)"
        surface="stations"
        variant="menu"
        @refused="$emit('refused', $event)"
      />
    </template>
    <template #cell-health="{ row }">
      <span v-if="row.health === null" class="inline-flex items-center gap-2 text-text-3"
        ><ApStatusMark state="off" />Not reported</span
      >
      <span v-else class="inline-flex items-center gap-2"
        ><ApStatusMark
          :state="
            row.health.status === 'nominal'
              ? 'nominal'
              : row.health.status === 'degraded'
                ? 'caution'
                : 'crit'
          "
        />{{
          row.health.status === "nominal"
            ? "Nominal"
            : row.health.status === "degraded"
              ? "Degraded"
              : "Down"
        }}</span
      >
    </template>
  </ApTable>
</template>
