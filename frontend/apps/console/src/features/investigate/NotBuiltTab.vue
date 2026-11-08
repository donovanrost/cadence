<script setup lang="ts">
import { ApEmptyState, ApPanel } from "@/ui";

/** Tabs other than Investigate aren't built yet (spec: temporary empty state). */
defineProps<{ tab: string }>();
</script>

<template>
  <ApPanel index="B1" :title="tab" flush class="flex-none">
    <ApEmptyState
      state="off"
      headline="Not built yet in the new console"
      sentence="Use the existing Cadence pages for this until it ships."
    />
  </ApPanel>
</template>
