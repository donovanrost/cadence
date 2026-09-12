<script setup lang="ts">
import type { WidgetPointPresentation } from "./WidgetPoint.contracts";

import ChartDataManagementStrip from "./ChartDataManagementStrip.vue";
import TelemetryChart from "./TelemetryChart.vue";

defineProps<{ presentation: WidgetPointPresentation }>();
</script>

<template>
  <template v-if="presentation.kind === 'value_tile'">
    <div :class="presentation.value.container_class">
      <span :class="presentation.value.class" v-bind="presentation.value.attrs">{{
        presentation.value.text
      }}</span>
      <span v-if="presentation.value.unit" :class="presentation.value.unit.class">{{
        presentation.value.unit.text
      }}</span>
    </div>
    <p :class="presentation.timestamp.class">{{ presentation.timestamp.text }}</p>
    <p
      v-if="presentation.comparison"
      :class="presentation.comparison.class"
      v-bind="presentation.comparison.attrs"
    >
      {{ presentation.comparison.text }}
    </p>
  </template>

  <div
    v-else-if="presentation.kind === 'time_series'"
    :class="presentation.stage.class"
    v-bind="presentation.stage.attrs"
  >
    <div
      v-if="presentation.data_management"
      :id="presentation.data_management.component_id"
      class="contents"
    >
      <ChartDataManagementStrip :presentation="presentation.data_management.presentation" />
    </div>
    <div :id="presentation.chart.component_id" :class="presentation.chart.class">
      <TelemetryChart v-bind="presentation.chart.props" />
    </div>
  </div>

  <template v-else>
    <div :class="presentation.badges.class">
      <span
        v-for="(badge, badgeIndex) in presentation.badges.items"
        :key="badgeIndex"
        :class="badge.class"
      >
        <span :class="badge.dot_class"></span>
        <span :class="badge.count_class">{{ badge.count }}</span>
        <span :class="badge.label_class">{{ badge.label }}</span>
      </span>
    </div>
    <div :class="presentation.spacecraft.class" v-bind="presentation.spacecraft.attrs">
      <span
        v-for="entry in presentation.spacecraft.items"
        :key="entry.key"
        :class="entry.class"
        v-bind="entry.attrs"
      ></span>
    </div>
  </template>
</template>
