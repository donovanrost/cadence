<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIconButton from "@cadence/ui/CadenceIconButton.vue";
import CadenceNoticeFrame from "@cadence/ui/CadenceNoticeFrame.vue";
import type { Notice } from "./useDashboardDirectory";

defineProps<{ notice: Notice }>();
const emit = defineEmits<{ dismiss: [] }>();
</script>

<template>
  <CadenceNoticeFrame
    id="dashboard-directory-notice"
    :tone="notice.tone"
    role="status"
    class="flex items-center gap-3"
  >
    <span class="flex-1">{{ notice.text }}</span>
    <CadenceButton v-if="notice.action" size="xs" variant="outline" @click="notice.action.run">
      {{ notice.action.label }}
    </CadenceButton>
    <CadenceIconButton icon="hero-x-mark" label="Dismiss" @click="emit('dismiss')" />
  </CadenceNoticeFrame>
</template>
