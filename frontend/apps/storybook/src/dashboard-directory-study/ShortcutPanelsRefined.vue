<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import ShortcutPanel from "./ShortcutPanel.vue";
import ShortcutRow from "./ShortcutRow.vue";
import { ago, type DirectoryStudy } from "./state";

const props = defineProps<{ study: DirectoryStudy }>();
const limit = 5;
const actions = props.study.actions;
</script>

<!-- Variation 1: the same two panels, equal height, with descriptions, unstar and "show all". -->
<template>
  <div class="grid gap-4 md:grid-cols-2">
    <ShortcutPanel
      label="Starred"
      icon="hero-star"
      :count="study.starred.length"
      empty="Star a dashboard in the list below to pin it here."
    >
      <template v-if="study.starred.length > limit" #action>
        <CadenceButton size="xs" variant="quiet" @click="actions.setStarredOnly(true)"
          >Show all</CadenceButton
        >
      </template>
      <ShortcutRow
        v-for="item in study.starred.slice(0, limit)"
        :key="item.id"
        :dashboard="item"
        :meta="`updated ${ago(item.updatedAt)}`"
        detail
        starrable
        @star="actions.toggleStar(item.id)"
      />
    </ShortcutPanel>
    <ShortcutPanel
      label="Recently viewed"
      icon="hero-clock"
      :count="study.recent.length"
      empty="Dashboards you open appear here."
    >
      <ShortcutRow
        v-for="item in study.recent.slice(0, limit)"
        :key="item.id"
        :dashboard="item"
        :meta="ago(item.lastViewedAt ?? 0)"
        detail
      />
    </ShortcutPanel>
  </div>
</template>
