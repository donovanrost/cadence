<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadencePaginationFrame from "@cadence/ui/CadencePaginationFrame.vue";

const props = defineProps<{ page: number; pages: number; total: number; shown: number }>();
const emit = defineEmits<{ page: [page: number] }>();
const first = () => (props.page - 1) * 50 + 1;
</script>

<template>
  <CadencePaginationFrame aria-label="Dashboard pages">
    <span class="font-mono text-xs text-base-content/70"
      >{{ first() }}–{{ first() + shown - 1 }} of {{ total }}</span
    >
    <div class="flex items-center gap-1">
      <CadenceButton
        size="xs"
        variant="quiet"
        :disabled="page === 1"
        @click="emit('page', page - 1)"
        >Previous</CadenceButton
      >
      <CadenceButton
        size="xs"
        variant="quiet"
        :disabled="page === pages"
        @click="emit('page', page + 1)"
        >Next</CadenceButton
      >
    </div>
  </CadencePaginationFrame>
</template>
