<script setup lang="ts">
import DirectoryListRow from "./DirectoryListRow.vue";
import type { StudyDashboard } from "./fixtures";
import type { DirectoryStudy } from "./state";

const props = defineProps<{ study: DirectoryStudy }>();
const emit = defineEmits<{ duplicate: [dashboard: StudyDashboard] }>();
const actions = props.study.actions;
</script>

<!-- A list, not a table: people scan names; tags and dates describe each row. -->
<template>
  <ul aria-label="Dashboards" class="divide-y divide-base-300/60">
    <DirectoryListRow
      v-for="dashboard in study.rows"
      :key="dashboard.id"
      :dashboard="dashboard"
      :author="study.author"
      :highlighted="study.highlighted.includes(dashboard.id)"
      :selected-tags="study.filters.tags"
      @star="actions.toggleStar(dashboard.id)"
      @tag="actions.toggleTag"
      @duplicate="emit('duplicate', dashboard)"
      @archive="actions.archive(dashboard.id)"
      @restore="actions.restore(dashboard.id)"
    />
  </ul>
</template>
