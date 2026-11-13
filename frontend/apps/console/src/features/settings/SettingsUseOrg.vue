<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApSheet } from "@/ui";

/** ux 823e4f7a1 (3): go back to the organization's values for one section, after a confirm. */
defineProps<{ missionName: string; orgName: string; section: string; busy: boolean }>();
const emit = defineEmits<{ confirm: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
function confirm() {
  sheet.value?.close();
  emit("confirm");
}
</script>

<template>
  <ApButton
    size="compact"
    variant="ghost"
    :disabled="busy"
    disabled-reason="Saving…"
    @click="sheet?.open()"
    >Use the organization's settings</ApButton
  >
  <ApSheet ref="sheet" title="Use the organization's settings" width="narrow">
    <p class="m-0 text-md text-text-2">
      {{ missionName }} will use {{ orgName }}'s {{ section }} settings. This mission's own values
      for it are discarded.
    </p>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton variant="danger" @click="confirm">Use the organization's settings</ApButton>
    </template>
  </ApSheet>
</template>
