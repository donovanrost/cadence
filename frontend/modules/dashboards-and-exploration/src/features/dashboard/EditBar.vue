<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";

defineProps<{ dirty: boolean; pending: boolean; widgets: number; sections: number }>();
const emit = defineEmits<{ addWidget: []; addSection: []; details: [] }>();
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-2 border-y border-base-300/60 py-2"
    role="toolbar"
    aria-label="Dashboard editing"
  >
    <CadenceButton variant="outline" size="sm" :disabled="pending" @click="emit('addWidget')">
      <CadenceIcon name="hero-plus" />Widget
    </CadenceButton>
    <CadenceButton variant="quiet" size="sm" :disabled="pending" @click="emit('addSection')">
      <CadenceIcon name="hero-rectangle-group" />Section
    </CadenceButton>
    <CadenceButton variant="quiet" size="sm" :disabled="pending" @click="emit('details')">
      <CadenceIcon name="hero-adjustments-horizontal" />Details &amp; defaults
    </CadenceButton>
    <span class="ml-auto font-mono text-xs text-base-content/60" aria-live="polite">
      {{ widgets }} widgets · {{ sections }} sections ·
      <span :class="dirty ? 'text-warning' : ''">{{
        pending ? "Applying…" : dirty ? "Unsaved changes" : "All changes saved"
      }}</span>
    </span>
  </div>
</template>
