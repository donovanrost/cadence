<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import ShortcutPanel from "./ShortcutPanel.vue";
import ShortcutRow from "./ShortcutRow.vue";
import StarredTile from "./StarredTile.vue";
import { ago, type DirectoryStudy } from "./state";

const props = defineProps<{ study: DirectoryStudy }>();
const actions = props.study.actions;
</script>

<!-- Variation 4: starred dashboards as navigation tiles; recently viewed as a list beside them. -->
<template>
  <div class="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_20rem]">
    <section aria-label="Starred">
      <h2 class="hud-label mb-2 flex items-center gap-1.5">
        <CadenceIcon name="hero-star" size="xs" />Starred
      </h2>
      <p v-if="study.starred.length === 0" class="text-sm text-base-content/70">
        Star a dashboard in the list below to pin it here.
      </p>
      <div v-else class="grid gap-3 sm:grid-cols-2 2xl:grid-cols-3">
        <StarredTile
          v-for="item in study.starred"
          :key="item.id"
          :dashboard="item"
          @star="actions.toggleStar(item.id)"
        />
      </div>
    </section>
    <ShortcutPanel
      label="Recently viewed"
      icon="hero-clock"
      :count="study.recent.length"
      empty="Dashboards you open appear here."
    >
      <ShortcutRow
        v-for="item in study.recent.slice(0, 3)"
        :key="item.id"
        :dashboard="item"
        :meta="ago(item.lastViewedAt ?? 0)"
      />
    </ShortcutPanel>
  </div>
</template>
