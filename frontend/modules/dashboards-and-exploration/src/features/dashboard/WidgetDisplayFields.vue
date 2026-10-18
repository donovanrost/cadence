<script setup lang="ts">
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceChoiceField from "@cadence/ui/CadenceChoiceField.vue";
import type { WidgetFields } from "./contracts";
import {
  axisOptions,
  fillOptions,
  flag,
  legendOptions,
  lineOptions,
  precisionOptions,
  windowOptions,
  withCurrent,
} from "./widget-form";

const fields = defineModel<WidgetFields>({ required: true });
const toggles = [
  ["show_min_max_band", "Min/max band"],
  ["span_gaps", "Connect gaps"],
  ["show_points", "Show points"],
  ["shared_tooltip", "Shared hover values"],
] as const;
const set = (key: keyof WidgetFields, value: boolean) => (fields.value[key] = String(value));
</script>

<template>
  <div class="space-y-3">
    <div class="grid gap-3 sm:grid-cols-2">
      <CadenceChoiceField
        id="widget-precision"
        v-model="fields.precision"
        label="Decimals"
        :options="withCurrent(precisionOptions, fields.precision)"
      />
      <CadenceChoiceField
        id="widget-window"
        v-model="fields.window_seconds"
        label="Default window"
        :options="withCurrent(windowOptions, fields.window_seconds)"
      />
    </div>
    <CadenceCheckbox
      v-if="fields.type === 'value_tile'"
      :model-value="flag(fields, 'show_unit')"
      @update:model-value="set('show_unit', $event)"
    >
      Show engineering unit
    </CadenceCheckbox>
    <template v-if="fields.type === 'time_series'">
      <CadenceChoiceField
        id="widget-legend"
        v-model="fields.legend_mode"
        label="Legend"
        :options="legendOptions"
      />
      <CadenceChoiceField
        id="widget-line"
        v-model="fields.line_width"
        label="Line width"
        :options="lineOptions"
      />
      <CadenceChoiceField
        id="widget-fill"
        v-model="fields.fill_opacity"
        label="Area fill"
        :options="withCurrent(fillOptions, fields.fill_opacity)"
      />
      <CadenceChoiceField
        id="widget-axes"
        v-model="fields.axis_mode"
        label="Value axes"
        :options="axisOptions"
      />
      <div class="grid gap-2 sm:grid-cols-2">
        <CadenceCheckbox
          v-for="[key, label] in toggles"
          :key="key"
          :model-value="flag(fields, key)"
          @update:model-value="set(key, $event)"
        >
          {{ label }}
        </CadenceCheckbox>
      </div>
    </template>
  </div>
</template>
