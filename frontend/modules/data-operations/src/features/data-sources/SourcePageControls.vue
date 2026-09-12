<script setup lang="ts">
import type { Page } from "./native-contract";
defineProps<{ id: string; label: string; page: Page<unknown>; disabled: boolean }>();
defineEmits<{ change: [page: number] }>();
</script>
<template>
  <nav :aria-label="label + ' pages'" class="flex flex-wrap items-center gap-2 pt-3 text-xs">
    <span>Page {{ page.page }}</span>
    <button
      :id="id + '-previous'"
      type="button"
      class="btn btn-xs btn-outline"
      :disabled="disabled || page.page <= 1"
      @click="$emit('change', page.page - 1)"
    >
      Previous
    </button>
    <button
      :id="id + '-next'"
      type="button"
      class="btn btn-xs btn-outline"
      :disabled="disabled || !page.has_next || page.page >= 1000000"
      @click="$emit('change', page.page + 1)"
    >
      Next
    </button>
  </nav>
</template>
