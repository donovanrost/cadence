<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { diffEdits, SchemaForm, type FormValues } from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApPanel, formatShort } from "@/ui";
import SettingsValues from "./SettingsValues.vue";
import {
  initialValues,
  sourceLabel,
  valueText,
  type SettingsField,
  type SettingsScope,
  type SettingsSection,
} from "./api.ts";
import { useSectionSave } from "./useSectionSave.ts";

/** One settings section: generated form for editors, values with their source for everyone. */
const props = defineProps<{ scope: SettingsScope; section: SettingsSection; canEdit: boolean }>();
const emit = defineEmits<{ saved: [] }>();
const before = ref<FormValues>({});
const values = ref<FormValues>({});
const errors = ref<Readonly<Record<string, string>>>({});
watch(
  () => props.section,
  (s) => {
    before.value = initialValues(s);
    values.value = initialValues(s);
  },
  { immediate: true },
);
const { busy, note, save } = useSectionSave(
  () => props.scope,
  () => props.section,
  () => emit("saved"),
);
const editable = computed(() => props.canEdit && props.section.locked !== true);
/** Mission level: where each value comes from, with reset for the ones set here. */
const sources = computed(() => (props.scope.kind === "mission" ? props.section.fields : []));
const meta = computed(() => {
  const v = props.section.version;
  return v
    ? `v${v.version} · ${formatShort(new Date(v.at))}${v.actor ? ` by ${v.actor.name}` : ""}`
    : undefined; // ux §7 #11: raw keys belong in Technical details, not the header.
});

function submit() {
  const edits = diffEdits(
    { kind: "settings", fields: props.section.fields },
    before.value,
    values.value,
  );
  if (!edits.ok) return void (errors.value = edits.errors);
  errors.value = {};
  if (edits.changes.length === 0)
    return void (note.value = { tone: "caution", text: "Nothing changed yet." });
  void save(Object.fromEntries(edits.changes.map((c) => [c.path, c.value])));
}
const reset = (f: SettingsField) =>
  void save({ [f.path]: null }, `${f.label} inherits again. Saved`);
</script>

<template>
  <ApPanel index="S1" :title="section.title" :meta="meta" :flush="!editable">
    <p
      v-if="section.purpose"
      class="m-0 mb-3 text-md text-text-3"
      :class="editable ? '' : 'border-b border-hairline px-4 py-2.5'"
    >
      {{ section.purpose }}
    </p>
    <ApCallout v-if="section.locked" tone="info"
      >The organization sets these and doesn't allow missions to override them.</ApCallout
    >
    <SettingsValues v-if="!editable" :fields="section.fields" :scope="scope.kind" />
    <div v-else class="flex flex-col gap-4">
      <SchemaForm
        v-model="values"
        :schema="{ kind: 'settings', fields: section.fields }"
        :errors="errors"
      />
      <ul v-if="sources.length > 0" class="m-0 flex list-none flex-col gap-1.5 p-0 text-sm">
        <li v-for="f in sources" :key="f.path" class="flex flex-wrap items-baseline gap-x-2">
          <span class="text-text-2">{{ f.label }}</span>
          <span class="font-mono text-xs text-text-4 uppercase">{{
            sourceLabel(f, scope.kind)
          }}</span>
          <template v-if="f.source === 'mission'">
            <span class="text-text-3">· org: {{ valueText(f, f.inherited_value) }}</span>
            <ApButton size="compact" :disabled="busy" disabled-reason="Saving…" @click="reset(f)"
              >Reset to inherited</ApButton
            >
          </template>
        </li>
      </ul>
      <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
      <div>
        <ApButton variant="primary" :disabled="busy" disabled-reason="Saving…" @click="submit"
          >Save</ApButton
        >
      </div>
    </div>
  </ApPanel>
</template>
