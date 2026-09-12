<script setup lang="ts">
import type { EditorSection, WidgetFields } from "./contracts";
const fields = defineModel<WidgetFields>({ required: true });
defineProps<{ sections: EditorSection[] }>();
const emit = defineEmits<{ typeChange: [] }>();
const types = [
  "value_tile",
  "time_series",
  "status_matrix",
  "data_table",
  "state_timeline",
  "event_timeline",
  "constellation_health",
];
const scopes = [
  "mission",
  "spacecraft",
  "contact",
  "ground_station",
  "source_endpoint",
  "transport",
  "link",
];
</script>
<template>
  <label class="editor-field" for="editor-widget-title"
    >Title<input
      id="editor-widget-title"
      v-model="fields.title"
      required
      maxlength="120"
      class="input input-bordered input-sm w-full"
  /></label>
  <div class="grid grid-cols-2 gap-3">
    <label class="editor-field" for="editor-widget-type"
      >Widget type<select
        id="editor-widget-type"
        v-model="fields.type"
        @change="emit('typeChange')"
        class="select select-bordered select-sm w-full"
      >
        <option v-for="type in types" :key="type" :value="type">
          {{ type.replaceAll("_", " ") }}
        </option>
      </select></label
    >
    <label class="editor-field" for="editor-widget-section"
      >Section<select
        id="editor-widget-section"
        v-model="fields.section_id"
        class="select select-bordered select-sm w-full"
      >
        <option value="">Unsectioned</option>
        <option v-for="section in sections" :key="section.id" :value="section.id">
          {{ section.title }}
        </option>
      </select></label
    >
  </div>
  <template v-if="!['event_timeline', 'constellation_health'].includes(fields.type)">
    <label class="editor-field" for="editor-widget-source"
      >Observable source<select
        id="editor-widget-source"
        v-model="fields.binding_source"
        class="select select-bordered select-sm w-full"
      >
        <option value="telemetry">Telemetry</option>
        <option value="operational_observables">Operational observables</option>
        <option v-if="fields.type === 'state_timeline'" value="limits">Limits</option>
      </select></label
    >
    <label class="editor-field" for="editor-widget-mode"
      >Scope<select
        id="editor-widget-mode"
        v-model="fields.mode"
        class="select select-bordered select-sm w-full"
      >
        <option value="context">Dashboard context</option>
        <option value="fixed">Specific spacecraft</option>
        <option value="scope">Specific resource</option>
        <option
          v-if="['time_series', 'status_matrix', 'data_table'].includes(fields.type)"
          value="repeat"
        >
          Repeat by resource
        </option>
      </select></label
    >
    <label v-if="fields.mode === 'fixed'" class="editor-field" for="editor-widget-spacecraft"
      >Spacecraft ID<input
        id="editor-widget-spacecraft"
        v-model="fields.spacecraft_id"
        required
        maxlength="256"
        class="input input-bordered input-sm w-full"
    /></label>
    <div v-if="fields.mode === 'scope'" class="grid grid-cols-2 gap-3">
      <label class="editor-field" for="editor-widget-scope-kind"
        >Resource kind<select
          id="editor-widget-scope-kind"
          v-model="fields.scope_kind"
          required
          class="select select-bordered select-sm w-full"
        >
          <option value="" disabled>Choose kind</option>
          <option v-for="scope in scopes" :key="scope" :value="scope">
            {{ scope.replaceAll("_", " ") }}
          </option>
        </select></label
      >
      <label class="editor-field" for="editor-widget-scope-id"
        >Resource ID<input
          id="editor-widget-scope-id"
          v-model="fields.scope_id"
          required
          maxlength="256"
          class="input input-bordered input-sm w-full"
      /></label>
    </div>
    <div v-if="fields.mode === 'repeat'" class="grid grid-cols-2 gap-3">
      <label class="editor-field" for="editor-widget-repeat"
        >Repeat over<select
          id="editor-widget-repeat"
          v-model="fields.repeat_over"
          class="select select-bordered select-sm w-full"
        >
          <option
            v-for="scope in ['spacecraft', 'contact', 'ground_station', 'transport', 'link']"
            :key="scope"
            :value="scope"
          >
            {{ scope.replaceAll("_", " ") }}
          </option>
        </select></label
      >
      <label class="editor-field" for="editor-widget-repeat-layout"
        >Arrangement<select
          id="editor-widget-repeat-layout"
          v-model="fields.repeat_layout"
          class="select select-bordered select-sm w-full"
        >
          <option value="wrap_grid">Wrap grid</option>
          <option value="row">Row</option>
          <option value="column">Column</option>
        </select></label
      >
      <label class="editor-field" for="editor-widget-repeat-max"
        >Maximum instances<input
          id="editor-widget-repeat-max"
          :value="fields.repeat_max_instances"
          @input="fields.repeat_max_instances = ($event.target as HTMLInputElement).value"
          type="number"
          min="1"
          max="24"
          required
          class="input input-bordered input-sm w-full"
      /></label>
    </div>
    <div class="grid grid-cols-2 gap-3">
      <label class="editor-field" for="editor-widget-precision"
        >Decimal places<input
          id="editor-widget-precision"
          :value="fields.precision"
          @input="fields.precision = ($event.target as HTMLInputElement).value"
          type="number"
          min="0"
          max="6"
          required
          class="input input-bordered input-sm w-full"
      /></label>
      <label class="editor-field" for="editor-widget-window"
        >Window (seconds)<input
          id="editor-widget-window"
          :value="fields.window_seconds"
          @input="fields.window_seconds = ($event.target as HTMLInputElement).value"
          type="number"
          min="60"
          max="3600"
          required
          class="input input-bordered input-sm w-full"
      /></label>
    </div>
    <label v-if="fields.type === 'value_tile'" class="flex items-center gap-2 text-xs"
      ><input
        id="editor-widget-show-unit"
        v-model="fields.show_unit"
        type="checkbox"
        true-value="true"
        false-value="false"
        class="checkbox checkbox-sm"
      />
      Show unit</label
    >
  </template>
  <fieldset v-if="fields.type === 'time_series'" class="border-t border-base-300 pt-4 space-y-3">
    <legend class="text-xs font-mono px-1">Chart presentation</legend>
    <div class="grid grid-cols-2 gap-3">
      <label class="editor-field" for="editor-widget-legend"
        >Legend<select
          id="editor-widget-legend"
          v-model="fields.legend_mode"
          class="select select-bordered select-sm w-full"
        >
          <option value="auto">Automatic</option>
          <option value="always">Always</option>
          <option value="hidden">Hidden</option>
        </select></label
      >
      <label class="editor-field" for="editor-widget-line"
        >Line width<select
          id="editor-widget-line"
          v-model="fields.line_width"
          class="select select-bordered select-sm w-full"
        >
          <option value="thin">Thin</option>
          <option value="normal">Normal</option>
          <option value="bold">Bold</option>
        </select></label
      >
      <label class="editor-field" for="editor-widget-fill"
        >Fill opacity (%)<input
          id="editor-widget-fill"
          :value="fields.fill_opacity"
          @input="fields.fill_opacity = ($event.target as HTMLInputElement).value"
          type="number"
          min="0"
          max="30"
          required
          class="input input-bordered input-sm w-full"
      /></label>
      <label class="editor-field" for="editor-widget-axis"
        >Axes<select
          id="editor-widget-axis"
          v-model="fields.axis_mode"
          class="select select-bordered select-sm w-full"
        >
          <option value="unit">Separate units</option>
          <option value="shared">Shared</option>
        </select></label
      >
    </div>
    <label
      v-for="[key, label] in [
        ['show_min_max_band', 'Min/max band'],
        ['span_gaps', 'Connect gaps'],
        ['show_points', 'Show points'],
        ['shared_tooltip', 'Shared tooltip'],
      ] as const"
      :key="key"
      class="flex items-center gap-2 text-xs"
      ><input
        :id="`editor-widget-${key}`"
        v-model="fields[key]"
        type="checkbox"
        true-value="true"
        false-value="false"
        class="checkbox checkbox-sm"
      />{{ label }}</label
    >
  </fieldset>
</template>
<style scoped>
.editor-field {
  display: grid;
  gap: 0.375rem;
  font-size: 0.75rem;
  min-width: 0;
}
</style>
