<script setup lang="ts">
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";
import CadenceHoverTableRow from "@cadence/ui/CadenceHoverTableRow.vue";
import DirectoryRowMenu from "./DirectoryRowMenu.vue";
import StarToggle from "./StarToggle.vue";
import TagChips from "./TagChips.vue";
import { dashboardPath, type StudyDashboard } from "./fixtures";
import { ago } from "./state";

defineProps<{
  dashboard: StudyDashboard;
  author: boolean;
  highlighted: boolean;
  selectedTags: readonly string[];
}>();
const emit = defineEmits<{
  star: [];
  tag: [tag: string];
  duplicate: [];
  archive: [];
  restore: [];
}>();
</script>

<template>
  <CadenceHoverTableRow :class="highlighted ? 'bg-primary/10' : ''" :data-dashboard="dashboard.id">
    <td class="max-w-0 w-1/2">
      <div class="flex items-center gap-2">
        <a
          :href="dashboardPath(dashboard.id)"
          class="truncate font-medium text-primary hover:underline"
          >{{ dashboard.name }}</a
        >
        <CadenceBadge v-if="dashboard.archived" tone="warning">Archived</CadenceBadge>
      </div>
      <p v-if="dashboard.description" class="truncate text-xs text-base-content/70">
        {{ dashboard.description }}
      </p>
    </td>
    <td>
      <TagChips :tags="dashboard.tags" :selected="selectedTags" @toggle="emit('tag', $event)" />
    </td>
    <td class="whitespace-nowrap">
      <span
        class="block text-sm text-base-content/70"
        :title="new Date(dashboard.updatedAt).toISOString()"
        >{{ ago(dashboard.updatedAt) }}</span
      >
      <span class="block text-xs text-base-content/60">{{ dashboard.updatedBy }}</span>
    </td>
    <td class="w-0 text-right">
      <div class="flex items-center justify-end gap-1">
        <StarToggle :dashboard="dashboard" @star="emit('star')" />
        <DirectoryRowMenu
          v-if="author"
          :dashboard="dashboard"
          @duplicate="emit('duplicate')"
          @archive="emit('archive')"
          @restore="emit('restore')"
        />
      </div>
    </td>
  </CadenceHoverTableRow>
</template>
