<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceOpsListFrame from "@cadence/ui/CadenceOpsListFrame.vue";
import CadenceSegmentedControl from "@cadence/ui/CadenceSegmentedControl.vue";
import ShortcutRow from "./ShortcutRow.vue";
import { ago, type DirectoryStudy } from "./state";

const props = defineProps<{ study: DirectoryStudy }>();
// Production would remember the chosen tab per person.
const tab = ref(props.study.starred.length ? "starred" : "recent");
const options = computed(() => [
  { value: "starred", label: `Starred · ${props.study.starred.length}` },
  { value: "recent", label: "Recently viewed" },
]);
const items = computed(() =>
  (tab.value === "starred" ? props.study.starred : props.study.recent).slice(0, 6),
);
const meta = (item: (typeof items.value)[number]) =>
  tab.value === "starred" ? item.tags.join(" · ") : ago(item.lastViewedAt ?? 0);
</script>

<!-- Variation 2: one full-width panel; a tab switches between starred and recent. -->
<template>
  <CadenceOpsListFrame aria-label="Your dashboards">
    <div class="flex items-center justify-between gap-3 border-b border-base-300 px-4 py-2">
      <h2 class="hud-label">Your dashboards</h2>
      <CadenceSegmentedControl v-model="tab" label="Show" size="xs" :options="options" />
    </div>
    <p v-if="items.length === 0" class="px-4 py-3 text-sm text-base-content/70">
      {{
        tab === "starred"
          ? "Star a dashboard in the list below to pin it here."
          : "Dashboards you open appear here."
      }}
    </p>
    <ul v-else class="grid md:grid-cols-2 xl:grid-cols-3">
      <ShortcutRow
        v-for="item in items"
        :key="item.id"
        :dashboard="item"
        :meta="meta(item)"
        detail
      />
    </ul>
  </CadenceOpsListFrame>
</template>
