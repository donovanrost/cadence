<script setup lang="ts">
import { computed } from "vue";

import DashboardWidgetHeader from "./DashboardWidgetHeader.vue";
import WidgetPoint from "./WidgetPoint.vue";
import WidgetRows from "./WidgetRows.vue";

type Classes = string | string[];
type Attributes = Record<string, string>;
type ButtonType = "button" | "submit" | "reset";

type HeaderPresentation = InstanceType<typeof DashboardWidgetHeader>["$props"]["presentation"];
type PointPresentation = InstanceType<typeof WidgetPoint>["$props"]["presentation"];
type RowsPresentation = InstanceType<typeof WidgetRows>["$props"]["presentation"];

type WidgetNoticePresentation = {
  kind: "notice" | "lifecycle";
  class: Classes;
  attrs: Attributes;
  text: string;
  actions: Array<{
    key: string;
    type: ButtonType;
    class: string;
    attrs: Attributes;
    icon: { name: string; class: string };
    text: string;
  }>;
};

type WidgetBodyPresentation = {
  kind:
    | "value_tile"
    | "time_series"
    | "status_matrix"
    | "data_table"
    | "state_timeline"
    | "event_timeline"
    | "constellation_health";
  root: { class: Classes; attrs: Attributes };
  notice: WidgetNoticePresentation | null;
  content:
    | { component: "WidgetPoint"; presentation: PointPresentation }
    | { component: "WidgetRows"; presentation: RowsPresentation }
    | null;
};

type DashboardWidgetPresentation = {
  component_id: string;
  header: HeaderPresentation;
  body: WidgetBodyPresentation;
};

const props = defineProps<{ presentation: DashboardWidgetPresentation }>();

// DASHBOARD_WIDGET_COMPOSITION_START
const dashboardWidgetComposition = (presentation: DashboardWidgetPresentation) => {
  const content = presentation.body.content;

  return {
    header: presentation.header,
    point: content?.component === "WidgetPoint" ? content.presentation : null,
    rows: content?.component === "WidgetRows" ? content.presentation : null,
  };
};
// DASHBOARD_WIDGET_COMPOSITION_END

const composition = computed(() => dashboardWidgetComposition(props.presentation));
</script>

<template>
  <div :id="composition.header.component_id" class="contents">
    <DashboardWidgetHeader :presentation="composition.header" />
  </div>

  <div :class="props.presentation.body.root.class" v-bind="props.presentation.body.root.attrs">
    <div
      v-if="props.presentation.body.notice"
      :class="props.presentation.body.notice.class"
      v-bind="props.presentation.body.notice.attrs"
    >
      <p v-if="props.presentation.body.notice.kind === 'lifecycle'">
        {{ props.presentation.body.notice.text }}
      </p>
      <template v-else>{{ props.presentation.body.notice.text }}</template>

      <div
        v-if="props.presentation.body.notice.actions.length > 0"
        class="mt-2 flex flex-wrap gap-1.5 font-sans"
      >
        <button
          v-for="action in props.presentation.body.notice.actions"
          :key="action.key"
          :type="action.type"
          :class="action.class"
          v-bind="action.attrs"
        >
          <span :class="[action.icon.name, action.icon.class]"></span>
          {{ action.text }}
        </button>
      </div>
    </div>

    <div v-if="composition.point" :id="composition.point.component_id" class="contents">
      <WidgetPoint :presentation="composition.point" />
    </div>

    <div v-else-if="composition.rows" :id="composition.rows.component_id" class="contents">
      <WidgetRows :presentation="composition.rows" />
    </div>
  </div>
</template>
