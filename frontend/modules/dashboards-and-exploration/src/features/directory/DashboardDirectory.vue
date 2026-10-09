<script setup lang="ts">
import { computed, ref } from "vue";
import DirectoryHeading from "./DirectoryHeading.vue";
import DirectoryNotice from "./DirectoryNotice.vue";
import DirectoryResults from "./DirectoryResults.vue";
import DirectoryShortcuts from "./DirectoryShortcuts.vue";
import DirectoryToolbar from "./DirectoryToolbar.vue";
import DuplicateDialog from "./DuplicateDialog.vue";
import FirstRun from "./FirstRun.vue";
import type { DashboardRow } from "./contracts";
import { useDashboardDirectory, type DirectoryProps } from "./useDashboardDirectory";

const props = defineProps<DirectoryProps>();
const { model, mission, filtered, pending, notice, highlighted, query, filters, actions } =
  useDashboardDirectory(props);
const duplicating = ref<DashboardRow | null>(null);
const firstRun = computed(
  () => model.value.total === 0 && !filtered.value && !model.value.filters.archived,
);

async function duplicate(name: string) {
  const source = duplicating.value;
  duplicating.value = null;
  if (source) await actions.duplicate(source, name);
}
</script>

<template>
  <section id="dashboard-directory-feature" class="space-y-4">
    <DirectoryHeading :mission="mission" :author="model.author" />
    <DirectoryNotice v-if="notice" :notice="notice" @dismiss="actions.dismiss" />
    <FirstRun
      v-if="firstRun"
      :mission="mission"
      :author="model.author"
      @archived="filters.showArchived(true)"
    />
    <template v-else>
      <DirectoryShortcuts
        v-if="!filtered"
        :mission="mission"
        :shortcuts="model.shortcuts"
        :pending="pending"
        @star="actions.star"
        @show-starred="filters.starredOnly(true)"
      />
      <DirectoryToolbar
        :query="query"
        :filters="model.filters"
        :tags="model.available_tags"
        @search="filters.search"
        @toggle-tag="filters.toggleTag"
        @starred="filters.starredOnly"
        @archived="filters.showArchived"
        @sort="filters.sort"
        @clear="filters.clear"
      />
      <DirectoryResults
        :model="model"
        :highlighted="highlighted"
        :pending="pending"
        @star="actions.star"
        @tag="filters.toggleTag"
        @duplicate="duplicating = $event"
        @archive="actions.archive"
        @restore="actions.restore"
        @page="filters.page"
        @clear="filters.clear"
      />
    </template>
    <DuplicateDialog
      :source="duplicating"
      :pending="pending"
      @close="duplicating = null"
      @confirm="duplicate"
    />
  </section>
</template>
