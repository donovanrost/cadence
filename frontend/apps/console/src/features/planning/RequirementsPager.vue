<script setup lang="ts">
import { ApButton } from "@/ui";

/** P4 paging: the list is most recently changed first, so Newer goes back a page. */
defineProps<{ page: number; nextPage: number | null; busy: boolean }>();
defineEmits<{ go: [page: number] }>();
</script>

<template>
  <div class="flex gap-2 border-t border-hairline px-4 py-2.5">
    <ApButton
      size="compact"
      :disabled="busy || page === 1"
      :disabled-reason="busy ? 'Loading…' : 'First page'"
      @click="$emit('go', page - 1)"
      >Newer</ApButton
    >
    <ApButton
      size="compact"
      :disabled="busy || nextPage === null"
      :disabled-reason="busy ? 'Loading…' : 'Last page'"
      @click="nextPage !== null && $emit('go', nextPage)"
      >Older</ApButton
    >
  </div>
</template>
