<script setup lang="ts">
import { computed } from "vue";
import ResumeCard from "./ResumeCard.vue";
import ShortcutPanel from "./ShortcutPanel.vue";
import ShortcutRow from "./ShortcutRow.vue";
import { ago, type DirectoryStudy } from "./state";

const props = defineProps<{ study: DirectoryStudy }>();
const last = computed(() => props.study.recent[0]);
const earlier = computed(() => props.study.recent.slice(1));
</script>

<!-- Variation 5: lead with the dashboard you were just using, in the range and spacecraft you used. -->
<template>
  <div class="grid gap-4 lg:grid-cols-3">
    <ResumeCard v-if="last" :dashboard="last" />
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
        :meta="`updated ${ago(item.updatedAt)}`"
      />
    </ShortcutPanel>
    <ShortcutPanel
      label="Also viewed"
      icon="hero-clock"
      :count="earlier.length"
      empty="Dashboards you open appear here."
    >
      <ShortcutRow
        v-for="item in earlier"
        :key="item.id"
        :dashboard="item"
        :meta="ago(item.lastViewedAt ?? 0)"
      />
    </ShortcutPanel>
  </div>
</template>
