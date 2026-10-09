<script setup lang="ts">
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import { dashboardPath, type StudyDashboard } from "./fixtures";

defineProps<{ starred: readonly StudyDashboard[]; recent: readonly StudyDashboard[] }>();
</script>

<template>
  <nav aria-label="Your dashboards" class="space-y-1.5 text-sm">
    <div
      v-for="group in [
        { label: 'Starred', icon: 'hero-star', items: starred },
        { label: 'Recently viewed', icon: 'hero-clock', items: recent },
      ] as const"
      v-show="group.items.length"
      :key="group.label"
      class="flex flex-wrap items-center gap-x-3 gap-y-1"
    >
      <span class="hud-label inline-flex w-40 shrink-0 items-center whitespace-nowrap gap-1.5"
        ><CadenceIcon :name="group.icon" size="xs" />{{ group.label }}</span
      >
      <a
        v-for="item in group.items"
        :key="item.id"
        :href="dashboardPath(item.id)"
        class="text-primary hover:underline"
        >{{ item.name }}</a
      >
    </div>
  </nav>
</template>
