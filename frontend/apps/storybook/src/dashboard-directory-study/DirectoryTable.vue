<script setup lang="ts">
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import DirectoryRow from "./DirectoryRow.vue";
import type { StudyDashboard } from "./fixtures";
import type { DirectoryStudy } from "./state";

const props = defineProps<{ study: DirectoryStudy }>();
const emit = defineEmits<{ duplicate: [dashboard: StudyDashboard] }>();
const actions = props.study.actions;
</script>

<template>
  <CadenceTableFrame>
    <thead>
      <tr>
        <th class="hud-label">Name</th>
        <th class="hud-label">Tags</th>
        <th class="hud-label">Updated</th>
        <th><span class="sr-only">Star and actions</span></th>
      </tr>
    </thead>
    <tbody>
      <DirectoryRow
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
    </tbody>
  </CadenceTableFrame>
</template>
