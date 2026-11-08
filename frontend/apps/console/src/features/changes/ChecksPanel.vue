<script setup lang="ts">
import { ApEmptyState, ApPanel } from "@/ui";

/**
 * K2 Checks (Changes.md §3): conflicts and validation from the server's dry run. Until the preview
 * endpoint ships the panel says so instead of implying the set is clean.
 */
</script>

<template>
  <ApPanel index="K2" title="Checks" flush>
    <ApEmptyState
      state="off"
      headline="Checks not available yet"
      sentence="Conflicts and validation run on the server before apply. They appear here when the preview endpoint ships; nothing has been checked yet."
    />
  </ApPanel>
</template>
