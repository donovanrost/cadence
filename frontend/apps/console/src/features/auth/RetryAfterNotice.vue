<script setup lang="ts">
import { ApCallout } from "@/ui";
import type { useRetryAfter } from "./retry-after.ts";

/**
 * The 429 attempt limit on a password form (a11y B6, ux #276): the m:ss countdown is shown but not
 * live; the wait is said once as an alert when the limit is hit, and "You can try again now."
 * once, politely, when it's over. The two live regions are always in the page, so they announce.
 */
defineProps<{ retry: ReturnType<typeof useRetryAfter> }>();
</script>

<template>
  <p class="sr-only" role="alert">{{ retry.said.value.alert }}</p>
  <p class="sr-only" role="status">{{ retry.said.value.status }}</p>
  <ApCallout v-if="retry.text.value" tone="caution" role="none">{{ retry.text.value }}</ApCallout>
</template>
