<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceEmptyStateFrame from "@cadence/ui/CadenceEmptyStateFrame.vue";
import CadenceOpsListFrame from "@cadence/ui/CadenceOpsListFrame.vue";
import DirectoryListRow from "./DirectoryListRow.vue";
import DirectoryPagination from "./DirectoryPagination.vue";
import type { DashboardRow, DirectoryModel } from "./contracts";
import { dashboardHref } from "./href";

defineProps<{ model: DirectoryModel; highlighted: readonly string[]; pending: boolean }>();
const emit = defineEmits<{
  star: [row: DashboardRow];
  tag: [tag: string];
  duplicate: [row: DashboardRow];
  archive: [row: DashboardRow];
  restore: [row: DashboardRow];
  page: [page: number];
  clear: [];
}>();
</script>

<!-- A list, not a table: people scan names; tags and dates describe each row. -->
<template>
  <CadenceOpsListFrame id="dashboard-directory-results" aria-label="Dashboard results">
    <CadenceEmptyStateFrame v-if="model.rows.length === 0" class="m-4">
      <template #title>No dashboards match</template>
      <template #description
        >Try a different search, or clear the tag and starred filters.</template
      >
      <template #action
        ><CadenceButton size="sm" @click="emit('clear')">Clear filters</CadenceButton></template
      >
    </CadenceEmptyStateFrame>
    <ul v-else aria-label="Dashboards" class="divide-y divide-base-300/60">
      <DirectoryListRow
        v-for="row in model.rows"
        :key="row.id"
        :row="row"
        :href="dashboardHref(model.mission_id, row.id)"
        :author="model.author"
        :highlighted="highlighted.includes(row.id)"
        :pending="pending"
        :selected-tags="model.filters.tags"
        @star="emit('star', row)"
        @tag="emit('tag', $event)"
        @duplicate="emit('duplicate', row)"
        @archive="emit('archive', row)"
        @restore="emit('restore', row)"
      />
    </ul>
    <DirectoryPagination
      v-if="model.pages > 1"
      :page="model.filters.page"
      :pages="model.pages"
      :total="model.total"
      :shown="model.rows.length"
      @page="emit('page', $event)"
    />
  </CadenceOpsListFrame>
</template>
