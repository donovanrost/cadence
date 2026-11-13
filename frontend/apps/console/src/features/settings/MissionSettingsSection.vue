<script setup lang="ts">
import { computed } from "vue";
import { useConsoleScope } from "@/shell";
import { ApCallout } from "@/ui";
import MissionSettingsField from "./MissionSettingsField.vue";
import {
  confirmsReset,
  resetLine,
  type SettingsField,
  type SettingsScope,
  type SettingsSection,
} from "./api.ts";
import { useSectionSave } from "./useSectionSave.ts";

/**
 * A mission's section, per field (ux SettingsAuditProviders.md › Settings; api 14455857d): a save
 * sends only that field's path; Reset sends null, so it follows the organization again.
 */
const props = defineProps<{ scope: SettingsScope; section: SettingsSection; canChange: boolean }>();
const emit = defineEmits<{ saved: [] }>();
const { busy, note, save } = useSectionSave(
  () => props.scope,
  () => props.section,
  () => emit("saved"),
);
const where = useConsoleScope();
const orgName = computed(() =>
  where.value.kind === "organization" || where.value.kind === "mission"
    ? where.value.organization.name
    : "the organization",
);
function reset(f: SettingsField) {
  void save({ [f.path]: null }, "Saved", (version) => resetLine(f, version));
}
function unchanged() {
  note.value = { tone: "caution", text: "Nothing changed yet." };
}
</script>

<template>
  <div
    class="grid grid-cols-1 gap-px bg-hairline"
    :class="section.fields.length > 1 ? 'md:grid-cols-2' : ''"
  >
    <MissionSettingsField
      v-for="f in section.fields"
      :key="f.path"
      :field="f"
      :can-change="canChange"
      :busy="busy"
      :confirm-reset="confirmsReset(section.key)"
      :org-name="orgName"
      @save="(v) => void save(v)"
      @reset="reset(f)"
      @unchanged="unchanged"
    />
  </div>
  <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
</template>
