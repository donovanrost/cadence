<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApSheet } from "@/ui";
import AdminModeForm from "./AdminModeForm.vue";

/** L6 step-up as a dialog (account menu, no-org page); the form itself is AdminModeForm. */
const emit = defineEmits<{ entered: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const form = ref<InstanceType<typeof AdminModeForm> | null>(null);

function open() {
  form.value?.reset();
  sheet.value?.open();
}
function entered() {
  sheet.value?.close();
  emit("entered");
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Admin mode" initial-focus="input">
    <AdminModeForm ref="form" @entered="entered">
      <template #actions>
        <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      </template>
    </AdminModeForm>
  </ApSheet>
</template>
