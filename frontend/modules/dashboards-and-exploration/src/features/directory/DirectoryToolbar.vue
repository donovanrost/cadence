<script setup lang="ts">
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import ActiveTags from "./ActiveTags.vue";
import SortMenu from "./SortMenu.vue";
import TagFilterMenu from "./TagFilterMenu.vue";
import type { DirectoryFilters, DirectorySort } from "./contracts";

defineProps<{ query: string; filters: DirectoryFilters; tags: readonly string[] }>();
const emit = defineEmits<{
  search: [query: string];
  toggleTag: [tag: string];
  starred: [value: boolean];
  archived: [value: boolean];
  sort: [sort: DirectorySort];
  clear: [];
}>();
</script>

<template>
  <div class="space-y-2">
    <div class="flex flex-wrap items-center gap-3">
      <!-- No CadenceSearchField yet; this is the daisyUI input-with-icon pattern. -->
      <label class="input input-sm min-w-64 flex-1">
        <CadenceIcon name="hero-magnifying-glass" />
        <input
          id="dashboard-directory-search"
          type="search"
          class="grow"
          aria-label="Search dashboards"
          placeholder="Search by name, description or tag"
          :value="query"
          @input="emit('search', ($event.target as HTMLInputElement).value)"
        />
      </label>
      <TagFilterMenu :tags="tags" :selected="filters.tags" @toggle="emit('toggleTag', $event)" />
      <CadenceCheckbox
        id="dashboard-directory-starred"
        :model-value="filters.starred"
        @update:model-value="emit('starred', $event)"
      >
        Starred
      </CadenceCheckbox>
      <CadenceCheckbox
        id="dashboard-directory-archived"
        :model-value="filters.archived"
        @update:model-value="emit('archived', $event)"
      >
        Show archived
      </CadenceCheckbox>
      <div class="ml-auto"><SortMenu :sort="filters.sort" @change="emit('sort', $event)" /></div>
    </div>
    <ActiveTags
      v-if="filters.tags.length"
      :tags="filters.tags"
      @toggle="emit('toggleTag', $event)"
      @clear="emit('clear')"
    />
  </div>
</template>
