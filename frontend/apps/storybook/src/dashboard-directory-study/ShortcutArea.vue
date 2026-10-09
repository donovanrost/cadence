<script setup lang="ts">
import QuickLinks from "./QuickLinks.vue";
import QuickPanels from "./QuickPanels.vue";
import ShortcutPanelsRefined from "./ShortcutPanelsRefined.vue";
import ShortcutResume from "./ShortcutResume.vue";
import ShortcutTabs from "./ShortcutTabs.vue";
import ShortcutTiles from "./ShortcutTiles.vue";
import type { DirectoryStudy, QuickAccess } from "./state";

defineProps<{ study: DirectoryStudy; variant: Exclude<QuickAccess, "none" | "rail"> }>();
</script>

<template>
  <QuickLinks v-if="variant === 'links'" :starred="study.starred" :recent="study.recent" />
  <QuickPanels v-else-if="variant === 'panels'" :starred="study.starred" :recent="study.recent" />
  <ShortcutPanelsRefined v-else-if="variant === 'refined'" :study="study" />
  <ShortcutTabs v-else-if="variant === 'tabbed'" :study="study" />
  <ShortcutTiles v-else-if="variant === 'tiles'" :study="study" />
  <ShortcutResume v-else :study="study" />
</template>
