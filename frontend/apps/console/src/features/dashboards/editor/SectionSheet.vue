<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApField, ApSheet, ApTextarea } from "@/ui";
import type { Command, Outline } from "./contracts.ts";
import { newId } from "./draft.ts";

/**
 * Add section / a section's Edit (ux Dashboards.md › Grid › 'Sections in edit mode'): one sheet
 * that stages add_section or update_section. The server keeps title ≤ 512, description ≤ 4096.
 */
type Section = Outline["sections"][number];
const emit = defineEmits<{ stage: [command: Command] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const editing = ref<string | null>(null);
const title = ref("");
const description = ref("");
const collapsed = ref(false);
const blocked = computed(() => (title.value.trim() ? null : "Give the section a title."));

function openFor(section: Section | null) {
  editing.value = section?.id ?? null;
  title.value = section?.title ?? "";
  description.value = section?.description ?? "";
  collapsed.value = section?.collapsed_by_default ?? false;
  sheet.value?.open();
}
function apply() {
  if (blocked.value) return;
  const input = {
    section_id: editing.value ?? newId("dash_section"),
    title: title.value.trim(),
    description: description.value.trim(),
    collapsed_by_default: collapsed.value,
  };
  emit(
    "stage",
    editing.value ? { event: "update_section", input } : { event: "add_section", input },
  );
  sheet.value?.close();
}
defineExpose({ openFor });
</script>

<template>
  <ApSheet ref="sheet" :title="editing ? 'Edit section' : 'New section'" initial-focus="input">
    <div class="flex flex-col gap-4">
      <ApField v-model="title" label="Title" required />
      <ApTextarea
        v-model="description"
        label="Description"
        hint="Shown under the title."
        :rows="2"
        :maxlength="4096"
      />
      <label class="flex items-start gap-2 text-md text-readout">
        <input
          v-model="collapsed"
          type="checkbox"
          class="mt-1 accent-[var(--color-readout)] [color-scheme:dark]"
        />
        <span class="flex flex-col">
          Start collapsed
          <span class="text-sm text-text-3">Viewers see only the title until they open it.</span>
        </span>
      </label>
    </div>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? ''"
        @click="apply"
        >{{ editing ? "Apply" : "Add section" }}</ApButton
      >
    </template>
  </ApSheet>
</template>
