<script setup lang="ts">
import { computed } from "vue";
import CadenceChoiceField from "@cadence/ui/CadenceChoiceField.vue";
import CadenceSegmentedControl from "@cadence/ui/CadenceSegmentedControl.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import type { ScopeOption, WidgetFields } from "./contracts";
import {
  modeOptions,
  repeatLayoutOptions,
  repeatOverOptions,
  scopeKindOptions,
  sourceOptions,
  withCurrent,
} from "./widget-form";

const props = defineProps<{ scopeOptions: readonly ScopeOption[] }>();
const fields = defineModel<WidgetFields>({ required: true });
const spacecraft = computed(() =>
  withCurrent(
    props.scopeOptions.map((o) => ({ value: o.id, label: o.name })),
    fields.value.spacecraft_id,
  ).filter((o) => o.value !== ""),
);
</script>

<template>
  <div class="space-y-3">
    <CadenceChoiceField
      id="widget-source"
      v-model="fields.binding_source"
      label="Data source"
      :options="withCurrent(sourceOptions(fields.type), fields.binding_source)"
    />
    <div class="grid gap-1.5">
      <span class="hud-label">Scope</span>
      <CadenceSegmentedControl
        v-model="fields.mode"
        label="Widget scope"
        :options="modeOptions(fields.type)"
      />
    </div>
    <CadenceChoiceField
      v-if="fields.mode === 'fixed'"
      id="widget-spacecraft"
      v-model="fields.spacecraft_id"
      label="Spacecraft"
      :options="spacecraft"
      placeholder="Choose a spacecraft"
      required
    />
    <div v-if="fields.mode === 'scope'" class="grid gap-3 sm:grid-cols-2">
      <CadenceChoiceField
        id="widget-scope-kind"
        v-model="fields.scope_kind"
        label="Resource kind"
        :options="scopeKindOptions"
        required
      />
      <CadenceTextField
        id="widget-scope-id"
        v-model="fields.scope_id"
        label="Resource ID"
        required
      />
    </div>
    <div v-if="fields.mode === 'repeat'" class="space-y-3">
      <CadenceChoiceField
        id="widget-repeat-over"
        v-model="fields.repeat_over"
        label="Repeat for each"
        :options="repeatOverOptions"
      />
      <CadenceChoiceField
        id="widget-repeat-layout"
        v-model="fields.repeat_layout"
        label="Arrange copies"
        :options="repeatLayoutOptions"
      />
      <CadenceChoiceField
        id="widget-repeat-max"
        v-model="fields.repeat_max_instances"
        label="At most"
        :options="
          withCurrent(
            ['4', '8', '12', '24'].map((v) => ({ value: v, label: v })),
            fields.repeat_max_instances,
          )
        "
      />
    </div>
  </div>
</template>
