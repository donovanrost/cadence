<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceToggle from "@cadence/ui/CadenceToggle.vue";
import type { StudyDashboard } from "./fixtures";

defineProps<{ dashboard: StudyDashboard }>();
const emit = defineEmits<{ star: [] }>();
</script>

<template>
  <CadenceToggle :pressed="dashboard.starred" @request-change="emit('star')">
    <button
      type="button"
      class="cadence-icon-button"
      :class="dashboard.starred ? 'text-warning' : ''"
      :aria-label="`Star ${dashboard.name}`"
    >
      <CadenceIcon :name="dashboard.starred ? 'hero-star-solid' : 'hero-star'" />
    </button>
  </CadenceToggle>
</template>
