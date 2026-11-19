<script setup lang="ts">
import { computed } from "vue";
import { ApSelect } from "@/ui";
import type { WidgetFieldKey } from "./contracts.ts";
import {
  axisOptions,
  fillOptions,
  legendOptions,
  lineOptions,
  precisionOptions,
  windowOptions,
  withCurrent,
} from "./widget-form.ts";

/** How the widget draws. Series colors are fixed by the chart grammar, not chosen here. */
const fields = defineModel<Record<WidgetFieldKey, string>>("fields", { required: true });
const bind = (key: WidgetFieldKey) =>
  computed({
    get: () => fields.value[key],
    set: (v: string) => (fields.value = { ...fields.value, [key]: v }),
  });
const flag = (key: WidgetFieldKey) =>
  computed({
    get: () => fields.value[key] === "true",
    set: (v: boolean) => (fields.value = { ...fields.value, [key]: String(v) }),
  });
const precision = bind("precision");
const windowSeconds = bind("window_seconds");
const legend = bind("legend_mode");
const line = bind("line_width");
const fill = bind("fill_opacity");
const axis = bind("axis_mode");
const showUnit = flag("show_unit");
const band = flag("show_min_max_band");
const gaps = flag("span_gaps");
const points = flag("show_points");
const tooltip = flag("shared_tooltip");
const series = computed(() => fields.value.type === "time_series");
const checks = computed(() =>
  series.value
    ? [
        { label: "Min–max envelope", model: band },
        { label: "Connect across gaps", model: gaps },
        { label: "Show points", model: points },
        { label: "Shared tooltip", model: tooltip },
      ]
    : fields.value.type === "value_tile"
      ? [{ label: "Show unit", model: showUnit }]
      : [],
);
</script>

<template>
  <div class="grid grid-cols-2 gap-3">
    <ApSelect
      v-model="precision"
      label="Decimals"
      :options="withCurrent(precisionOptions, precision)"
    />
    <ApSelect
      v-model="windowSeconds"
      label="Widget window"
      :options="withCurrent(windowOptions, windowSeconds)"
    />
    <template v-if="series">
      <ApSelect v-model="legend" label="Legend" :options="withCurrent(legendOptions, legend)" />
      <ApSelect v-model="line" label="Line" :options="withCurrent(lineOptions, line)" />
      <ApSelect v-model="fill" label="Fill" :options="withCurrent(fillOptions, fill)" />
      <ApSelect v-model="axis" label="Y axis" :options="withCurrent(axisOptions, axis)" />
    </template>
  </div>
  <label v-for="c in checks" :key="c.label" class="flex items-center gap-2 text-md text-readout">
    <input
      v-model="c.model.value"
      type="checkbox"
      class="accent-[var(--color-readout)] [color-scheme:dark]"
    />
    {{ c.label }}
  </label>
</template>
