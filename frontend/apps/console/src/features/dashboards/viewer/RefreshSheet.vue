<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApOption, ApSheet } from "@/ui";
import { refreshWords } from "./refresh-words.ts";
import { refreshChoices, type RefreshChoice } from "./useDashboardView.ts";

/**
 * ⋯ › Refresh on a phone (ux Dashboards.md §Phone): the interval choices that the desktop header
 * shows as a select. Apply commits, so arrowing through the radios doesn't close the sheet.
 */
const props = defineProps<{ refresh: RefreshChoice }>();
const emit = defineEmits<{ pick: [choice: RefreshChoice] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const choice = ref<RefreshChoice | null>(null);
const title = (c: RefreshChoice) => {
  const words = refreshWords(c);
  return words.charAt(0).toUpperCase() + words.slice(1);
};
function open() {
  choice.value = props.refresh;
  sheet.value?.open();
}
function apply() {
  if (choice.value) emit("pick", choice.value);
  sheet.value?.close();
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Refresh" initial-focus="input:checked">
    <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
      <legend class="ap-label mb-2">How often live values refresh</legend>
      <ApOption
        v-for="c in refreshChoices"
        :key="c.value"
        v-model="choice"
        :value="c.value"
        name="dashboard-refresh"
        :title="title(c.value)"
      />
    </fieldset>
    <template #footer>
      <ApButton variant="secondary" class="mr-auto" @click="sheet?.close()">Cancel</ApButton>
      <ApButton variant="primary" @click="apply">Apply</ApButton>
    </template>
  </ApSheet>
</template>
