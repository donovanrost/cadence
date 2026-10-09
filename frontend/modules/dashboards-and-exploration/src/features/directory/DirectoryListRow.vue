<script setup lang="ts">
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";
import DirectoryRowMenu from "./DirectoryRowMenu.vue";
import StarToggle from "./StarToggle.vue";
import TagChips from "./TagChips.vue";
import type { DashboardRow } from "./contracts";
import { ago } from "./format";

defineProps<{
  row: DashboardRow;
  href: string;
  author: boolean;
  highlighted: boolean;
  pending: boolean;
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
    :id="`dashboard-${row.id}`"
    class="flex flex-wrap items-center gap-x-4 gap-y-1 border-l-2 border-l-transparent px-4 py-2.5 transition-colors hover:border-l-primary/60"
    :class="highlighted ? 'bg-primary/10' : ''"
    :data-starred="row.starred"
    :data-archived="row.archived"
  >
    <div class="flex min-w-0 flex-1 basis-96 items-baseline gap-3">
      <!-- Archived dashboards cannot be opened; the name stays plain text until restored. -->
      <a
        v-if="!row.archived"
        :href="href"
        class="max-w-[60%] shrink-0 truncate font-medium text-primary hover:underline"
        >{{ row.name }}</a
      >
      <span v-else class="max-w-[60%] shrink-0 truncate font-medium text-base-content/70">{{
        row.name
      }}</span>
      <CadenceBadge v-if="row.archived" tone="warning">Archived</CadenceBadge>
      <span v-if="row.description" class="truncate text-sm text-base-content/70">{{
        row.description
      }}</span>
    </div>
    <div class="ml-auto flex flex-wrap items-center justify-end gap-x-4 gap-y-1">
      <TagChips
        class="md:w-44 md:justify-end"
        :tags="row.tags"
        :selected="selectedTags"
        @toggle="emit('tag', $event)"
      />
      <span class="truncate text-right text-xs text-base-content/60 md:w-40">
        <time v-if="row.updated_at" :datetime="row.updated_at">{{ ago(row.updated_at) }}</time>
        <template v-if="row.updated_by"> · {{ row.updated_by }}</template>
      </span>
      <div class="flex items-center gap-1">
        <StarToggle v-if="!row.archived" :row="row" :disabled="pending" @star="emit('star')" />
        <DirectoryRowMenu
          v-if="author"
          :row="row"
          :href="href"
          :disabled="pending"
          @duplicate="emit('duplicate')"
          @archive="emit('archive')"
          @restore="emit('restore')"
        />
      </div>
    </div>
  </li>
</template>
