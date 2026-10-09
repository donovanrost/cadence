<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceOpsListFrame from "@cadence/ui/CadenceOpsListFrame.vue";
import { dashboardPath, type StudyDashboard } from "./fixtures";
import { ago } from "./state";

const props = defineProps<{
  starred: readonly StudyDashboard[];
  recent: readonly StudyDashboard[];
}>();
const groups = [
  {
    label: "Starred",
    icon: "hero-star",
    items: () => props.starred,
    empty: "Star a dashboard to keep it here.",
  },
  {
    label: "Recently viewed",
    icon: "hero-clock",
    items: () => props.recent,
    empty: "Dashboards you open appear here.",
  },
] as const;
</script>

<template>
  <div class="grid gap-4 md:grid-cols-2">
    <CadenceOpsListFrame v-for="group in groups" :key="group.label" :aria-label="group.label">
      <h2 class="hud-label flex items-center gap-1.5 border-b border-base-300 px-4 py-2">
        <CadenceIcon :name="group.icon" size="xs" />{{ group.label }}
      </h2>
      <p v-if="group.items().length === 0" class="px-4 py-3 text-sm text-base-content/70">
        {{ group.empty }}
      </p>
      <ul v-else class="divide-y divide-base-300/60">
        <li
          v-for="item in group.items()"
          :key="item.id"
          class="flex items-center justify-between gap-3 px-4 py-2"
        >
          <a :href="dashboardPath(item.id)" class="truncate text-sm text-primary hover:underline">{{
            item.name
          }}</a>
          <span class="shrink-0 text-xs text-base-content/60">
            {{ group.label === "Starred" ? item.tags.join(" · ") : ago(item.lastViewedAt ?? 0) }}
          </span>
        </li>
      </ul>
    </CadenceOpsListFrame>
  </div>
</template>
