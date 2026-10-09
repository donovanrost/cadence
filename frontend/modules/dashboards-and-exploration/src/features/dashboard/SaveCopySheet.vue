<script setup lang="ts">
import { ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import type { DashboardPageState } from "./useDashboardPage";

const props = defineProps<{ state: DashboardPageState; name: string }>();
const emit = defineEmits<{ close: [] }>();
const title = ref(`Copy of ${props.name}`);
</script>

<template>
  <form class="space-y-4" @submit.prevent="title.trim() && state.saveAsCopy(title.trim())">
    <p class="text-sm text-base-content/70">
      Saves the dashboard as you see it now, including unsaved changes, as a new dashboard. This
      dashboard is left unchanged.
    </p>
    <CadenceTextField id="dashboard-copy-name" v-model="title" label="Name" required />
    <footer class="flex justify-end gap-2 border-t border-base-300/60 pt-4">
      <CadenceButton variant="quiet" size="sm" @click="emit('close')">Cancel</CadenceButton>
      <CadenceButton
        type="submit"
        variant="primary"
        size="sm"
        :loading="state.pending.value"
        :disabled="!title.trim()"
      >
        Save copy
      </CadenceButton>
    </footer>
  </form>
</template>
