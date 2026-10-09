<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceToggle from "@cadence/ui/CadenceToggle.vue";
import type { DashboardRow } from "./contracts";

defineProps<{ row: DashboardRow; disabled: boolean }>();
const emit = defineEmits<{ star: [] }>();
</script>

<template>
  <CadenceToggle :pressed="row.starred" :disabled="disabled" @request-change="emit('star')">
    <button
      type="button"
      class="cadence-icon-button disabled:opacity-40"
      :class="row.starred ? 'text-warning' : ''"
      :aria-label="`Star ${row.name}`"
      :disabled="disabled"
    >
      <CadenceIcon :name="row.starred ? 'hero-star-solid' : 'hero-star'" />
    </button>
  </CadenceToggle>
</template>
