<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { diffEdits, SchemaForm, type FormValues } from "@/features/changes/index.ts";
import { canAdministerOrganization, useConsoleScope, useSession } from "@/shell";
import { ApButton, ApCallout, ApPanel, ApTag, formatShort } from "@/ui";
import MissionSettingsSection from "./MissionSettingsSection.vue";
import SettingsValues from "./SettingsValues.vue";
import SuspendGrantsCallout from "./SuspendGrantsCallout.vue";
import {
  initialValues,
  sectionTag,
  setHereCount,
  type SettingsScope,
  type SettingsSection,
} from "./api.ts";
import { disabledValues, lockedLine } from "./governance.ts";
import { useSectionSave } from "./useSectionSave.ts";

/**
 * One settings section. A mission's is per field (ux SettingsAuditProviders.md › Settings: each field
 * its own source, Override / Reset to inherited); the organization's is one form, its source on the
 * header.
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
const { busy, note, pending, save, confirmSuspension, cancelSuspension } = useSectionSave(
  () => props.scope,
  () => props.section,
  () => emit("saved"),
);
// #510 (api-ops): editing the form while the suspension callout is open drops the hold, so
// Confirm never saves values other than the ones on screen.
watch(values, () => cancelSuspension(), { deep: true });
const mission = computed(() => props.scope.kind === "mission");
const headerTag = computed(() =>
  mission.value ? setHereCount(props.section) : sectionTag(props.section, props.scope.kind),
);
const canChange = computed(() => props.canEdit && props.section.locked !== true);
/** ux U96: a locked mission section offers its organization's settings to an organization admin. */
const where = useConsoleScope();
const session = useSession();
const orgAdmin = computed(
  () =>
    (where.value.kind === "mission" || where.value.kind === "organization") &&
    canAdministerOrganization(session, where.value.organization),
);
/** The organization's form; a mission's fields edit one at a time. */
const editable = computed(() => !mission.value && canChange.value);
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
</script>

<template>
  <ApPanel index="S1" :title="section.title" :meta="meta" :flush="!editable">
    <!-- ux: a mission's fields carry their own tags; its header counts those set here. -->
    <template v-if="headerTag" #header><ApTag state="off" :label="headerTag" /></template>
    <p
      v-if="section.purpose"
      class="m-0 mb-3 text-md text-text-3"
      :class="editable ? '' : 'border-b border-hairline px-4 py-2.5'"
    >
      {{ section.purpose }}
    </p>
    <ApCallout v-if="section.locked" tone="info"
      >{{ lockedLine(section.key) }}
      <template v-if="mission && orgAdmin" #action>
        <ApButton
          size="compact"
          variant="ghost"
          :to="{ name: 'org.settings', params: { section: section.key } }"
          >Open organization settings</ApButton
        >
      </template>
    </ApCallout>
    <MissionSettingsSection
      v-if="mission"
      :scope="scope"
      :section="section"
      :can-change="canChange"
      @saved="$emit('saved')"
    />
    <SettingsValues v-else-if="!editable" :fields="section.fields" />
    <div v-else class="flex flex-col gap-4">
      <SchemaForm
        v-model="values"
        :schema="{ kind: 'settings', fields: section.fields }"
        :errors="errors"
        :disabled-values="disabledValues(section.fields)"
      />
      <SuspendGrantsCallout
        v-if="pending"
        :pending="pending"
        :busy="busy"
        @confirm="confirmSuspension"
        @cancel="cancelSuspension"
      />
      <ApCallout v-else-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
      <div v-if="!pending" class="flex flex-wrap gap-2">
        <ApButton variant="primary" :disabled="busy" disabled-reason="Saving…" @click="submit"
          >Save</ApButton
        >
      </div>
    </div>
  </ApPanel>
</template>
