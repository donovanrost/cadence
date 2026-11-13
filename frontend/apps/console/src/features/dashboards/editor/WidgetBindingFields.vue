<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { ApField, ApSelect } from "@/ui";
import type { WidgetFieldKey } from "./contracts.ts";
import ObservablePicker from "./ObservablePicker.vue";
import {
  bindsObservables,
  modeOptions,
  observableLimit,
  repeatOverOptions,
  scopeKindOptions,
  sourceOptions,
  typeOptions,
  withCurrent,
} from "./widget-form.ts";

/** What the widget shows and what it's bound to. Limits and units come from the catalog, never here. */
const props = defineProps<{
  missionId: MissionId;
  dashboardId: string;
  baseVersion: number;
  sections: readonly { id: string; title: string }[];
  spacecraft: readonly { id: string; name: string }[];
}>();
const fields = defineModel<Record<WidgetFieldKey, string>>("fields", { required: true });
const observables = defineModel<readonly string[]>("observables", { required: true });
const bind = (key: WidgetFieldKey) =>
  computed({
    get: () => fields.value[key],
    set: (v: string) => (fields.value = { ...fields.value, [key]: v }),
  });
const type = bind("type");
const title = bind("title");
const section = bind("section_id");
const source = bind("binding_source");
const mode = bind("mode");
const spacecraftId = bind("spacecraft_id");
const scopeKind = bind("scope_kind");
const scopeId = bind("scope_id");
const repeatOver = bind("repeat_over");
const sectionOptions = computed(() => [
  { value: "", label: "No section" },
  ...props.sections.map((s) => ({ value: s.id, label: s.title })),
]);
const spacecraftOptions = computed(() =>
  props.spacecraft.map((s) => ({ value: s.id, label: s.name })),
);
</script>

<template>
  <ApField v-model="title" label="Title" required />
  <ApSelect v-model="type" label="Widget" :options="withCurrent(typeOptions, type)" />
  <ApSelect v-model="section" label="Section" :options="sectionOptions" />
  <template v-if="bindsObservables(type)">
    <ApSelect v-model="source" label="Source" :options="withCurrent(sourceOptions(type), source)" />
    <ApSelect v-model="mode" label="Spacecraft" :options="withCurrent(modeOptions(type), mode)" />
    <ApSelect
      v-if="mode === 'fixed'"
      v-model="spacecraftId"
      label="Which spacecraft"
      mono
      placeholder="Choose a spacecraft"
      :options="spacecraftOptions"
    />
    <template v-if="mode === 'scope'">
      <ApSelect
        v-model="scopeKind"
        label="Resource kind"
        :options="withCurrent(scopeKindOptions, scopeKind)"
      />
      <ApField v-model="scopeId" label="Resource id" mono />
    </template>
    <ApSelect
      v-if="mode === 'repeat'"
      v-model="repeatOver"
      label="Repeat over"
      :options="withCurrent(repeatOverOptions, repeatOver)"
    />
    <ObservablePicker
      v-model="observables"
      :mission-id="missionId"
      :dashboard-id="dashboardId"
      :base-version="baseVersion"
      :fields="fields"
      :limit="observableLimit(type)"
    />
  </template>
</template>
