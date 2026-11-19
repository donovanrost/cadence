<script setup lang="ts">
import type { ModelHold } from "./holds.ts";

/**
 * U65: a HOLD that needs a catalog revision approved links to its approval page ('Open rev 4'),
 * where an org admin approves it. The server's sentence says why.
 */
defineProps<{ holds: readonly ModelHold[] }>();
</script>

<template>
  <div
    v-for="h in holds"
    :key="h.revisionId"
    class="border-t border-hairline px-4 py-2.5 text-sm text-text-2"
  >
    <RouterLink
      :to="{ name: 'setup.catalog.model', params: { revisionId: h.revisionId } }"
      class="text-primary no-underline hover:underline"
      >{{
        h.catalogRevisionNumber === null
          ? "Open the revision"
          : `Open rev ${h.catalogRevisionNumber}`
      }}</RouterLink
    >
  </div>
</template>
