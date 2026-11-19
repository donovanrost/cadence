<script setup lang="ts">
import { RouterLink } from "vue-router";
import type { DirectoryRow } from "./api.ts";

/** The row's link (rule: the Name is the row's navigation), with its star and archived tag. */
defineProps<{ row: DirectoryRow }>();
</script>

<template>
  <span class="flex min-w-0 items-center gap-2">
    <span v-if="row.starred" class="text-text-3" aria-label="Starred">★</span>
    <RouterLink
      :to="{ name: 'ops.dashboard', params: { dashboardId: row.id } }"
      class="min-w-0 truncate text-readout underline-offset-2 hover:underline"
      >{{ row.name }}</RouterLink
    >
    <span v-if="row.archived" class="font-display text-xs uppercase tracking-tag text-text-4"
      >Archived</span
    >
  </span>
</template>
