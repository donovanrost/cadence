<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceEmptyStateFrame from "@cadence/ui/CadenceEmptyStateFrame.vue";
import CadenceOpsListFrame from "@cadence/ui/CadenceOpsListFrame.vue";
import DirectoryList from "./DirectoryList.vue";
import DirectoryPagination from "./DirectoryPagination.vue";
import DirectoryTable from "./DirectoryTable.vue";
import type { StudyDashboard } from "./fixtures";
import type { DirectoryStudy, Presentation } from "./state";

defineProps<{ study: DirectoryStudy; presentation: Presentation }>();
const emit = defineEmits<{ duplicate: [dashboard: StudyDashboard] }>();
</script>

<template>
  <CadenceOpsListFrame aria-label="Dashboard results">
    <CadenceEmptyStateFrame v-if="study.rows.length === 0" class="m-4">
      <template #title>No dashboards match</template>
      <template #description
        >Try a different search, or clear the tag and starred filters.</template
      >
      <template #action>
        <CadenceButton size="sm" @click="study.actions.clearFilters">Clear filters</CadenceButton>
      </template>
    </CadenceEmptyStateFrame>
    <DirectoryTable
      v-else-if="presentation === 'table'"
      :study="study"
      @duplicate="emit('duplicate', $event)"
    />
    <DirectoryList v-else :study="study" @duplicate="emit('duplicate', $event)" />
    <DirectoryPagination v-if="study.pages > 1" :study="study" />
  </CadenceOpsListFrame>
</template>
