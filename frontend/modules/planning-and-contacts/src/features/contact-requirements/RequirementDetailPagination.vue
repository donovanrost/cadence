<script setup lang="ts">
import type { RequirementDetail, PageKey } from "./OpsContactRequirementShow.contracts";
import { pageHref } from "./requirement-detail";
const props = defineProps<{
  detail: RequirementDetail;
  section: "versions" | "runs" | "searches" | "opportunities";
}>();
defineEmits<{ navigate: [event: MouseEvent] }>();
const href = (n: number) => pageHref(props.detail, `${props.section}_page` as PageKey, n);
</script>
<template>
  <nav
    :aria-label="`${section} pages`"
    class="flex flex-wrap items-center justify-between gap-3 border-t border-base-300 px-4 py-3 font-mono text-xs"
  >
    <a
      v-if="detail[section].page > 1"
      :id="`${section}-previous-page`"
      :href="href(detail[section].page - 1)"
      data-phx-link="redirect"
      data-phx-link-state="push"
      class="text-primary underline"
      @click="$emit('navigate', $event)"
      >Previous</a
    >
    <span class="text-base-content/55">Page {{ detail[section].page }}</span>
    <a
      v-if="detail[section].more && detail[section].page < 1000000"
      :id="`${section}-next-page`"
      :href="href(detail[section].page + 1)"
      data-phx-link="redirect"
      data-phx-link-state="push"
      class="text-primary underline"
      @click="$emit('navigate', $event)"
      >Next</a
    >
    <span v-if="detail[section].more && detail[section].page === 1000000" role="status"
      >History page limit reached.</span
    >
  </nav>
</template>
