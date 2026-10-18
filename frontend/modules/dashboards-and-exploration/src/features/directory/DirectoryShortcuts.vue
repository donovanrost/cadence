<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import ShortcutPanel from "./ShortcutPanel.vue";
import ShortcutRow from "./ShortcutRow.vue";
import type { DashboardRow, DirectoryModel } from "./contracts";
import { ago } from "./format";
import { dashboardHref } from "./href";

defineProps<{ mission: string; shortcuts: DirectoryModel["shortcuts"]; pending: boolean }>();
const emit = defineEmits<{ star: [row: DashboardRow]; showStarred: [] }>();
const limit = 5;
</script>

<!-- Your dashboards: equal-height starred and recently viewed panels above the list. -->
<template>
  <div id="dashboard-directory-shortcuts" class="grid gap-4 md:grid-cols-2">
    <ShortcutPanel
      label="Starred"
      icon="hero-star"
      :count="shortcuts.starred.length"
      empty="Star a dashboard in the list below to pin it here."
    >
      <template v-if="shortcuts.starred.length > limit" #action>
        <CadenceButton size="xs" variant="quiet" @click="emit('showStarred')"
          >Show all</CadenceButton
        >
      </template>
      <ShortcutRow
        v-for="row in shortcuts.starred.slice(0, limit)"
        :key="row.id"
        :row="row"
        :href="dashboardHref(mission, row.id)"
        :meta="row.updated_at ? `updated ${ago(row.updated_at)}` : ''"
        :disabled="pending"
        starrable
        @star="emit('star', row)"
      />
    </ShortcutPanel>
    <ShortcutPanel
      label="Recently viewed"
      icon="hero-clock"
      :count="shortcuts.recent.length"
      empty="Dashboards you open appear here."
    >
      <ShortcutRow
        v-for="row in shortcuts.recent"
        :key="row.id"
        :row="row"
        :href="dashboardHref(mission, row.id)"
        :meta="ago(row.viewed_at)"
      />
    </ShortcutPanel>
  </div>
</template>
