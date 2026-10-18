<script setup lang="ts">
import { computed } from "vue";
import type { WorkspacePlacement, WorkspaceSnapshot } from "../workspace/contracts";
import { hasData } from "./widget-data";
import ValueTileWidget from "./widgets/ValueTileWidget.vue";
import TimeSeriesWidget from "./widgets/TimeSeriesWidget.vue";
import TableWidget from "./widgets/TableWidget.vue";
import StateTimelineWidget from "./widgets/StateTimelineWidget.vue";
import EventTimelineWidget from "./widgets/EventTimelineWidget.vue";
import ConstellationHealthWidget from "./widgets/ConstellationHealthWidget.vue";

const props = defineProps<{
  placement: WorkspacePlacement;
  context: WorkspaceSnapshot["context"];
  live: boolean;
  now: number;
  group: string;
  chartId: string;
}>();
const unavailable: Record<NonNullable<WorkspacePlacement["reason"]>, string> = {
  unsupported_widget: "This widget type is not supported here.",
  missing_result: "This widget did not resolve. Check its bindings.",
  invalid_frame: "This widget's data could not be displayed.",
};
const message = computed(() => {
  if (props.placement.status === "unavailable")
    return unavailable[props.placement.reason ?? "missing_result"];
  if (!hasData(props.placement)) return "No data in this time range.";
  return null;
});
const type = computed(() => props.placement.widget?.type);
</script>

<template>
  <div class="relative min-h-0 flex-1" :data-workspace-widget-body="placement.id">
    <p
      v-if="message"
      class="absolute inset-0 grid place-items-center px-4 text-center text-xs text-base-content/60"
    >
      {{ message }}
    </p>
    <ValueTileWidget v-else-if="type === 'value_tile'" :placement="placement" />
    <TimeSeriesWidget
      v-else-if="type === 'time_series'"
      :placement="placement"
      :context="context"
      :live="live"
      :group="group"
      :chart-id="chartId"
    />
    <TableWidget
      v-else-if="type === 'data_table' || type === 'status_matrix'"
      :placement="placement"
    />
    <StateTimelineWidget v-else-if="type === 'state_timeline'" :placement="placement" :now="now" />
    <EventTimelineWidget v-else-if="type === 'event_timeline'" :placement="placement" />
    <ConstellationHealthWidget v-else-if="type === 'constellation_health'" :placement="placement" />
  </div>
</template>
