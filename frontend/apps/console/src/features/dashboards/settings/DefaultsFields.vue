<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchSpacecraftDirectory } from "@/features/spacecraft/index.ts";
import { ApField, ApSelect } from "@/ui";
import { rangePresets, type DefaultsForm } from "./defaults.ts";

/** General › Defaults: the range and spacecraft the dashboard opens with (ux Dashboards.md). */
const props = defineProps<{ missionId: MissionId; errors: Readonly<Record<string, string>> }>();
const form = defineModel<DefaultsForm>({ required: true });
const directory = useRemoteQuery(() => props.missionId, fetchSpacecraftDirectory);
const timeOptions = computed(() => [
  { value: "", label: "None (the viewer's own)" },
  ...rangePresets,
  ...(form.value.time &&
  form.value.time !== "absolute" &&
  !rangePresets.some((p) => p.value === form.value.time)
    ? [{ value: form.value.time, label: form.value.time }]
    : []),
  { value: "absolute", label: "Fixed window" },
]);
const scopeOptions = [
  { value: "", label: "None" },
  { value: "context", label: "Chosen when viewing" },
  { value: "fixed", label: "One spacecraft" },
  { value: "fleet", label: "Whole fleet" },
];
const spacecraft = computed(() =>
  directory.state.value.status === "ready"
    ? directory.state.value.value.spacecraft.map((s) => ({ value: s.id, label: s.name }))
    : [],
);
const set = <K extends keyof DefaultsForm>(k: K, v: DefaultsForm[K]) =>
  (form.value = { ...form.value, [k]: v });
const setScope = (v: string) => {
  if (v === "" || v === "context" || v === "fixed" || v === "fleet") set("scope", v);
};
</script>

<template>
  <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
    <ApSelect
      :model-value="form.time"
      label="Default range"
      :options="timeOptions"
      @update:model-value="set('time', $event)"
    />
    <ApSelect
      :model-value="form.scope"
      label="Default spacecraft"
      :options="scopeOptions"
      @update:model-value="setScope"
    />
    <template v-if="form.time === 'absolute'">
      <ApField
        :model-value="form.from"
        label="From (UTC)"
        mono
        :error="errors['from'] ?? null"
        @update:model-value="set('from', $event)"
      />
      <ApField
        :model-value="form.to"
        label="To (UTC)"
        mono
        :error="errors['to'] ?? null"
        @update:model-value="set('to', $event)"
      />
    </template>
    <ApSelect
      v-if="form.scope === 'fixed'"
      :model-value="form.spacecraftId"
      label="Spacecraft"
      :options="spacecraft"
      placeholder="Choose…"
      :error="errors['spacecraftId'] ?? null"
      @update:model-value="set('spacecraftId', $event)"
    />
  </div>
</template>
