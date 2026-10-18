<script setup lang="ts">
import StarToggle from "./StarToggle.vue";
import { dashboardPath, type StudyDashboard } from "./fixtures";
import { ago } from "./state";

defineProps<{ dashboard: StudyDashboard }>();
const emit = defineEmits<{ star: [] }>();
</script>

<!-- A navigation card: the whole tile opens the dashboard, so it earns the corner brackets. -->
<template>
  <article
    class="hud-corners relative flex flex-col border border-base-300 bg-base-100 p-3 transition-colors hover:border-primary/60"
  >
    <div class="flex items-start gap-2">
      <a
        :href="dashboardPath(dashboard.id)"
        class="min-w-0 flex-1 truncate font-semibold text-primary after:absolute after:inset-0"
      >
        {{ dashboard.name }}
      </a>
      <div class="relative z-10 -mr-1 -mt-1">
        <StarToggle :dashboard="dashboard" @star="emit('star')" />
      </div>
    </div>
    <p class="mt-1 line-clamp-2 min-h-8 text-xs text-base-content/70">
      {{ dashboard.description }}
    </p>
    <div class="mt-3 flex items-center justify-between gap-2 text-xs text-base-content/60">
      <span class="truncate font-mono">{{ dashboard.tags.join(" · ") }}</span>
      <span class="shrink-0">{{ ago(dashboard.updatedAt) }}</span>
    </div>
  </article>
</template>
