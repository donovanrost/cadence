<script setup lang="ts">
import StarToggle from "./StarToggle.vue";
import { dashboardPath, type StudyDashboard } from "./fixtures";

withDefaults(
  defineProps<{ dashboard: StudyDashboard; meta: string; detail?: boolean; starrable?: boolean }>(),
  { detail: false, starrable: false },
);
const emit = defineEmits<{ star: [] }>();
</script>

<template>
  <li class="flex min-h-11 items-center gap-3 px-4 py-1.5">
    <div class="min-w-0 flex-1">
      <a
        :href="dashboardPath(dashboard.id)"
        class="block truncate text-sm text-primary hover:underline"
      >
        {{ dashboard.name }}
      </a>
      <p v-if="detail && dashboard.description" class="truncate text-xs text-base-content/70">
        {{ dashboard.description }}
      </p>
    </div>
    <span class="shrink-0 text-xs text-base-content/60">{{ meta }}</span>
    <StarToggle v-if="starrable" :dashboard="dashboard" @star="emit('star')" />
  </li>
</template>
