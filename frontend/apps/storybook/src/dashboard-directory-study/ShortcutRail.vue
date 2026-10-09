<script setup lang="ts">
import ShortcutPanel from "./ShortcutPanel.vue";
import ShortcutRow from "./ShortcutRow.vue";
import { ago, type DirectoryStudy } from "./state";

defineProps<{ study: DirectoryStudy }>();
</script>

<!-- Variation 3: shortcuts beside the list, so they never push it down and stay while searching. -->
<template>
  <aside aria-label="Your dashboards" class="space-y-4 xl:sticky xl:top-4">
    <ShortcutPanel
      label="Starred"
      icon="hero-star"
      :count="study.starred.length"
      empty="Star a dashboard to pin it here."
    >
      <ShortcutRow
        v-for="item in study.starred"
        :key="item.id"
        :dashboard="item"
        :meta="item.tags[0] ?? ''"
      />
    </ShortcutPanel>
    <ShortcutPanel
      label="Recently viewed"
      icon="hero-clock"
      :count="study.recent.length"
      empty="Dashboards you open appear here."
    >
      <ShortcutRow
        v-for="item in study.recent"
        :key="item.id"
        :dashboard="item"
        :meta="ago(item.lastViewedAt ?? 0)"
      />
    </ShortcutPanel>
  </aside>
</template>
