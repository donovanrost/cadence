<script setup lang="ts">
import { ApEmptyState, ApPanel } from "@/ui";

/** K1 with nothing to review: the server doesn't serve change sets, or nothing is staged. */
defineProps<{ reason: "unavailable" | "nothing" }>();
</script>

<template>
  <ApPanel index="K1" title="Changes" flush>
    <ApEmptyState
      v-if="reason === 'unavailable'"
      state="off"
      headline="Change sets not available yet"
      sentence="This server doesn't serve mission change sets to the console yet."
    />
    <ApEmptyState
      v-else
      data-changes-empty
      headline="Nothing staged"
      sentence="Edits in Setup collect here before they reach the fleet."
    />
  </ApPanel>
</template>
