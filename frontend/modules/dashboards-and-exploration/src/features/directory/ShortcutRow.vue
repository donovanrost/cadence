<script setup lang="ts">
import StarToggle from "./StarToggle.vue";
import type { DashboardRow } from "./contracts";

withDefaults(
  defineProps<{
    row: DashboardRow;
    href: string;
    meta: string;
    starrable?: boolean;
    disabled?: boolean;
  }>(),
  { starrable: false, disabled: false },
);
const emit = defineEmits<{ star: [] }>();
</script>

<template>
  <li class="flex min-h-11 items-center gap-3 px-4 py-1.5">
    <div class="min-w-0 flex-1">
      <a :href="href" class="block truncate text-sm text-primary hover:underline">{{ row.name }}</a>
      <p v-if="row.description" class="truncate text-xs text-base-content/70">
        {{ row.description }}
      </p>
    </div>
    <span class="shrink-0 text-xs text-base-content/60">{{ meta }}</span>
    <StarToggle v-if="starrable" :row="row" :disabled="disabled" @star="emit('star')" />
  </li>
</template>
