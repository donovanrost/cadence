<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadencePaginationFrame from "@cadence/ui/CadencePaginationFrame.vue";
import type { DirectoryStudy } from "./state";

const props = defineProps<{ study: DirectoryStudy }>();
const actions = props.study.actions;
</script>

<template>
  <CadencePaginationFrame>
    <span class="font-mono text-xs text-base-content/70">{{ study.range }}</span>
    <div class="flex items-center gap-1">
      <CadenceButton
        size="xs"
        variant="quiet"
        :disabled="study.filters.page === 1"
        @click="actions.setPage(study.filters.page - 1)"
        >Previous</CadenceButton
      >
      <CadenceButton
        size="xs"
        variant="quiet"
        :disabled="study.filters.page === study.pages"
        @click="actions.setPage(study.filters.page + 1)"
        >Next</CadenceButton
      >
    </div>
  </CadencePaginationFrame>
</template>
