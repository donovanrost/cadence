<script setup lang="ts">
import { ApCallout } from "@/ui";
import MissionSettingsField from "./MissionSettingsField.vue";
import type { SettingsScope, SettingsSection } from "./api.ts";
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
function reset(path: string, label: string) {
  void save({ [path]: null }, `${label} follows the organization again. Saved`);
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
      @save="(v) => void save(v)"
      @reset="reset(f.path, f.label)"
      @unchanged="unchanged"
    />
  </div>
  <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
</template>
