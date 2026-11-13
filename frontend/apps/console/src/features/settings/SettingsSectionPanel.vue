<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { diffEdits, SchemaForm, type FormValues } from "@/features/changes/index.ts";
import { useConsoleScope } from "@/shell";
import { ApButton, ApCallout, ApPanel, ApTag, formatShort } from "@/ui";
import SettingsUseOrg from "./SettingsUseOrg.vue";
import SettingsValues from "./SettingsValues.vue";
import {
  initialValues,
  sectionSource,
  sectionTag,
  type SettingsScope,
  type SettingsSection,
} from "./api.ts";
import { useSectionSave } from "./useSectionSave.ts";

/**
 * One settings section (ux 823e4f7a1, section-level overrides): the source tag on the header. A
 * mission's inherited section reads as text until `Override for this mission`; an overridden one is
 * editable and can go back to the organization's settings.
 */
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
const where = useConsoleScope();
const names = computed(() => ({
  org:
    where.value.kind === "organization" || where.value.kind === "mission"
      ? where.value.organization.name
      : "the organization",
  mission: where.value.kind === "mission" ? where.value.mission.name : "This mission",
}));
const inherited = computed(
  () => props.scope.kind === "mission" && sectionSource(props.section) !== "mission",
);
const overriding = ref(false);
watch(
  () => props.section,
  () => (overriding.value = false),
);
const canChange = computed(() => props.canEdit && props.section.locked !== true);
/** The form shows for the org, for an overridden mission section, or once Override is chosen. */
const editable = computed(() => canChange.value && (!inherited.value || overriding.value));
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
/** All nulls clear the mission's copy: the section inherits again (ConsoleSettings.save). */
const useOrg = () =>
  void save(
    Object.fromEntries(props.section.fields.map((f) => [f.path, null])),
    `${props.section.title} follows the organization again. Saved`,
  );
</script>

<template>
  <ApPanel index="S1" :title="section.title" :meta="meta" :flush="!editable">
    <template #header><ApTag state="off" :label="sectionTag(section, scope.kind)" /></template>
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
    <template v-if="!editable">
      <SettingsValues :fields="section.fields" :inherited="inherited" />
      <div v-if="inherited && canChange" class="px-4 py-3">
        <ApButton size="compact" @click="overriding = true">Override for this mission</ApButton>
      </div>
    </template>
    <div v-else class="flex flex-col gap-4">
      <ApCallout v-if="inherited" tone="info"
        >Overriding copies all of this section's organization values to {{ names.mission }}. They
        stop following organization changes until you go back to the organization's
        settings.</ApCallout
      >
      <SchemaForm
        v-model="values"
        :schema="{ kind: 'settings', fields: section.fields }"
        :errors="errors"
      />
      <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
      <div class="flex flex-wrap gap-2">
        <ApButton variant="primary" :disabled="busy" disabled-reason="Saving…" @click="submit"
          >Save</ApButton
        >
        <ApButton v-if="inherited" variant="ghost" @click="overriding = false">Cancel</ApButton>
        <SettingsUseOrg
          v-if="scope.kind === 'mission' && !inherited"
          :mission-name="names.mission"
          :org-name="names.org"
          :section="section.title"
          :busy="busy"
          @confirm="useOrg"
        />
      </div>
    </div>
  </ApPanel>
</template>
