<script setup lang="ts">
import { ref, watch } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceDialog from "@cadence/ui/CadenceDialog.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import type { StudyDashboard } from "./fixtures";

const props = defineProps<{ source: StudyDashboard | null }>();
const emit = defineEmits<{ close: []; confirm: [name: string] }>();
const name = ref("");
watch(
  () => props.source,
  (source) => (name.value = source ? `${source.name} copy` : ""),
);

function confirm() {
  if (name.value.trim()) emit("confirm", name.value.trim());
}
</script>

<template>
  <CadenceDialog
    :open="source !== null"
    title="Duplicate dashboard"
    :description="`Creates a new dashboard from the current version of “${source?.name}”. Stars and version history stay with the original.`"
    @update:open="(open) => open || emit('close')"
  >
    <form id="duplicate-dashboard-form" @submit.prevent="confirm">
      <CadenceTextField id="duplicate-dashboard-name" v-model="name" label="Name" required />
    </form>
    <template #actions>
      <CadenceButton variant="quiet" size="sm" @click="emit('close')">Cancel</CadenceButton>
      <CadenceButton
        variant="primary"
        size="sm"
        type="submit"
        form="duplicate-dashboard-form"
        :disabled="!name.trim()"
        >Duplicate</CadenceButton
      >
    </template>
  </CadenceDialog>
</template>
