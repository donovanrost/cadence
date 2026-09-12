<script setup lang="ts">
import type { PageKey, PlanDetail } from "./OpsContactPlanShow.contracts";
import { reviewHref } from "./plan-detail";
defineProps<{
  detail: PlanDetail;
  pageKey: PageKey;
  page: number;
  more: boolean;
  disabled: boolean;
}>();
</script>
<template>
  <nav
    :id="pageKey + '-navigation'"
    :aria-label="pageKey.replaceAll('_', ' ')"
    class="mt-4 flex items-center gap-4 text-sm"
    @click="disabled && $event.preventDefault()"
  >
    <a
      v-if="page > 1"
      :id="pageKey + '-previous'"
      :href="reviewHref(detail, detail.plan.version, pageKey, page - 1)"
      :aria-disabled="disabled"
      class="text-primary underline"
      >Previous</a
    >
    <span>Page {{ page }}</span>
    <a
      v-if="more"
      :id="pageKey + '-next'"
      :href="reviewHref(detail, detail.plan.version, pageKey, page + 1)"
      :aria-disabled="disabled"
      class="text-primary underline"
      >Next</a
    >
  </nav>
</template>
