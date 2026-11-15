<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApCallout, useNow } from "@/ui";
import {
  expiredLine,
  partialApproval,
  planOfDayRoute,
  supersededByLine,
  type Expired,
  type SupersededBy,
} from "./lifecycle.ts";

/**
 * U61 on K1: the plan that replaced this one (with Open), and after an approval that left passes
 * out because they had already started, the partial result with those passes under `Show N`.
 */
const props = defineProps<{
  day: string;
  supersededBy: SupersededBy | null;
  expired: Expired | null;
}>();
const now = useNow();
const showExpired = ref(false);
const replaced = computed(() =>
  props.supersededBy ? supersededByLine(props.supersededBy, now.value) : null,
);
const expiredLines = computed(() =>
  (props.expired?.items ?? []).map((item) => expiredLine(item, now.value)),
);
</script>

<template>
  <ApCallout v-if="supersededBy && replaced" tone="stale">
    <span class="flex flex-wrap items-center gap-x-3 gap-y-1">
      <span>{{ replaced }}</span>
      <ApButton variant="ghost" size="compact" :to="planOfDayRoute(day, supersededBy.plan_id)"
        >Open R{{ supersededBy.revision }}</ApButton
      >
    </span>
  </ApCallout>
  <ApCallout v-if="expired && expired.count > 0" tone="info">
    <span class="flex flex-col gap-1">
      <span class="flex flex-wrap items-center gap-x-3 gap-y-1">
        <span>{{ partialApproval(expired) }}</span>
        <ApButton
          v-if="expiredLines.length > 0"
          variant="ghost"
          size="compact"
          :aria-expanded="showExpired"
          @click="showExpired = !showExpired"
          >{{ showExpired ? "Hide" : `Show ${expired.count}` }}</ApButton
        >
      </span>
      <span v-if="showExpired" class="flex max-h-64 flex-col gap-0.5 overflow-y-auto">
        <span
          v-for="(line, i) in expiredLines"
          :key="i"
          class="font-mono text-sm text-text-2 tabular"
          >{{ line }}</span
        >
      </span>
    </span>
  </ApCallout>
</template>
