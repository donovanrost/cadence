<script setup lang="ts">
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import ActiveTags from "./ActiveTags.vue";
import SortMenu from "./SortMenu.vue";
import TagFilterMenu from "./TagFilterMenu.vue";
import type { DirectoryStudy } from "./state";

const props = defineProps<{ study: DirectoryStudy }>();
const actions = props.study.actions;
</script>

<template>
  <div class="space-y-2">
    <div class="flex flex-wrap items-center gap-3">
      <!-- No CadenceSearchField yet; this is the daisyUI input-with-icon pattern. -->
      <label class="input input-sm min-w-64 flex-1">
        <CadenceIcon name="hero-magnifying-glass" class="text-base-content/60" />
        <input
          type="search"
          class="grow"
          aria-label="Search dashboards"
          placeholder="Search by name, description or tag"
          :value="study.filters.query"
          @input="actions.search(($event.target as HTMLInputElement).value)"
        />
      </label>
      <TagFilterMenu
        :tags="study.tags"
        :selected="study.filters.tags"
        @toggle="actions.toggleTag"
      />
      <CadenceCheckbox
        :model-value="study.filters.starred"
        @update:model-value="actions.setStarredOnly"
      >
        Starred
      </CadenceCheckbox>
      <CadenceCheckbox
        :model-value="study.filters.archived"
        @update:model-value="actions.setArchived"
      >
        Show archived
      </CadenceCheckbox>
      <div class="ml-auto"><SortMenu :sort="study.filters.sort" @change="actions.setSort" /></div>
    </div>
    <ActiveTags
      :tags="study.filters.tags"
      @toggle="actions.toggleTag"
      @clear="actions.clearFilters"
    />
  </div>
</template>
