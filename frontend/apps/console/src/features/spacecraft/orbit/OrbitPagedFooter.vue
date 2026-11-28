<script setup lang="ts">
import { describeApiError, type ApiError } from "@/api";
import { ApButton, formatCount } from "@/ui";

/**
 * `N shown · Load more` under a paged list (the audit log's footer). The button stays and is
 * disabled on the last page, so focus never drops to <body> (a11y A5).
 */
defineProps<{
  shown: number;
  hasMore: boolean;
  loading: boolean;
  error: ApiError | null;
  /** What runs out on the last page: "No older element sets". */
  noMore: string;
}>();
defineEmits<{ more: [] }>();
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-2.5 text-sm text-text-3"
  >
    <span>{{ formatCount(shown) }} shown</span>
    <ApButton
      size="compact"
      :disabled="loading || !hasMore"
      :disabled-reason="loading ? 'Loading…' : noMore"
      @click="$emit('more')"
      >Load more</ApButton
    >
    <!-- B6: it answers the person's own click, so an alert, always mounted so it's announced;
      usePagedQuery clears moreError as Load more starts, so a repeat failure is said again. -->
    <span role="alert" class="text-caution-text">{{
      error ? `Couldn't load more: ${describeApiError(error)}` : ""
    }}</span>
  </div>
</template>
