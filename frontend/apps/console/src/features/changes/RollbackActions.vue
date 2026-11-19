<script setup lang="ts">
import { ApButton } from "@/ui";

/** Stage rollback (danger tone only here, Changes.md §4) and Cancel. */
defineProps<{ to: number; blocked: string | null }>();
defineEmits<{ stage: []; cancel: [] }>();
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <ApButton
      variant="danger"
      :disabled="blocked !== null"
      :disabled-reason="blocked ?? ''"
      @click="$emit('stage')"
      >Stage rollback to <span class="font-mono normal-case">r{{ to }}</span></ApButton
    >
    <ApButton variant="ghost" @click="$emit('cancel')">Cancel</ApButton>
  </div>
</template>
