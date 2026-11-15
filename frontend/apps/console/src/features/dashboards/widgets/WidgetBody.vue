<script setup lang="ts">
import { computed } from "vue";
import type { WorkspacePlacement, WorkspaceSnapshot } from "../model/snapshot.ts";
import { hasData } from "../model/widget-data.ts";
import ValueTileWidget from "./ValueTileWidget.vue";
import TimeSeriesWidget from "./TimeSeriesWidget.vue";
import TableWidget from "./TableWidget.vue";
import StateTimelineWidget from "./StateTimelineWidget.vue";
import EventTimelineWidget from "./EventTimelineWidget.vue";
import ConstellationHealthWidget from "./ConstellationHealthWidget.vue";

/** Dispatches a placement to its renderer. Errors stay inside the widget; the grid never breaks. */
const props = defineProps<{
  placement: WorkspacePlacement;
  context: WorkspaceSnapshot["context"];
  now: number;
  group: string;
  chartId: string;
}>();
const unavailable: Readonly<
  Record<Extract<WorkspacePlacement, { status: "unavailable" }>["reason"], string>
> = {
  unsupported_widget: "This widget type isn't supported here.",
  missing_result: "This widget didn't resolve. Check its bindings.",
  invalid_frame: "This widget's data can't be displayed.",
  unrecognized: "This widget isn't available.",
};
const ready = computed(() => (props.placement.status === "ready" ? props.placement : null));
const message = computed(() => {
  if (props.placement.status === "unavailable") return unavailable[props.placement.reason];
  if (props.placement.widget.type === "unrecognized") return unavailable.unsupported_widget;
  // A time series draws its frame on an empty range (bands and marks still matter; ux, Overlays).
  if (!hasData(props.placement) && props.placement.widget.type !== "time_series")
    return "No data in this range.";
  return null;
});
</script>

<template>
  <div class="relative h-full min-h-0" :data-workspace-widget-body="placement.id">
    <p
      v-if="message || !ready"
      class="absolute inset-0 grid place-items-center px-4 text-center text-sm text-text-3"
    >
      {{ message }}
    </p>
    <ValueTileWidget v-else-if="ready.widget.type === 'value_tile'" :placement="ready" />
    <TimeSeriesWidget
      v-else-if="ready.widget.type === 'time_series'"
      :placement="ready"
      :context="context"
      :group="group"
      :chart-id="chartId"
      :now="now"
    />
    <TableWidget
      v-else-if="ready.widget.type === 'data_table' || ready.widget.type === 'status_matrix'"
      :placement="ready"
    />
    <StateTimelineWidget
      v-else-if="ready.widget.type === 'state_timeline'"
      :placement="ready"
      :now="now"
    />
    <EventTimelineWidget v-else-if="ready.widget.type === 'event_timeline'" :placement="ready" />
    <ConstellationHealthWidget
      v-else-if="ready.widget.type === 'constellation_health'"
      :placement="ready"
    />
  </div>
</template>
