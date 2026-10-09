<script setup lang="ts">
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";
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
  <li
    class="flex flex-wrap items-center gap-x-4 gap-y-1 border-l-2 border-l-transparent px-4 py-2.5 transition-colors hover:border-l-primary/60"
    :class="highlighted ? 'bg-primary/10' : ''"
    :data-dashboard="dashboard.id"
  >
    <div class="flex min-w-0 flex-1 basis-96 items-baseline gap-3">
      <a
        :href="dashboardPath(dashboard.id)"
        class="max-w-[60%] shrink-0 truncate font-medium text-primary hover:underline"
      >
        {{ dashboard.name }}
      </a>
      <CadenceBadge v-if="dashboard.archived" tone="warning">Archived</CadenceBadge>
      <span v-if="dashboard.description" class="truncate text-sm text-base-content/70">{{
        dashboard.description
      }}</span>
    </div>
    <div class="ml-auto flex flex-wrap items-center justify-end gap-x-4 gap-y-1">
      <TagChips
        class="md:w-44 md:justify-end"
        :tags="dashboard.tags"
        :selected="selectedTags"
        @toggle="emit('tag', $event)"
      />
      <span class="truncate text-right text-xs text-base-content/60 md:w-40">
        <time :datetime="new Date(dashboard.updatedAt).toISOString()">{{
          ago(dashboard.updatedAt)
        }}</time>
        · {{ dashboard.updatedBy }}
      </span>
      <div class="flex items-center gap-1">
        <StarToggle :dashboard="dashboard" @star="emit('star')" />
        <DirectoryRowMenu
          v-if="author"
          :dashboard="dashboard"
          @duplicate="emit('duplicate')"
          @archive="emit('archive')"
          @restore="emit('restore')"
        />
      </div>
    </div>
  </li>
</template>
