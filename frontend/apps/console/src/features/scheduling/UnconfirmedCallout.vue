<script setup lang="ts">
import { computed } from "vue";
import { ApCallout, formatCountdown, useNow } from "@/ui";
import type { PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";
import { unconfirmedView } from "./unconfirmed.ts";

/**
 * U30 caution block, shared by K1 and K2 (exported): who hasn't confirmed what, and the passes
 * soonest first with T− to the first. No actions until domain offers a resolution (#53).
 */
const props = defineProps<{
  plan: PlanDetail;
  nameOf: (id: string | null) => SpacecraftName | null;
}>();
const now = useNow();
const view = computed(() => unconfirmedView(props.plan, props.nameOf));
</script>

<template>
  <ApCallout v-if="view" tone="caution">
    <span class="flex flex-col gap-1">
      <span>{{ view.headline }}</span>
      <span
        v-for="(row, i) in view.rows"
        :key="row.id"
        class="font-mono text-sm text-text-2 tabular"
        >{{ row.text
        }}<template v-if="i === 0"> · {{ formatCountdown(row.startsAt, now) }}</template></span
      >
    </span>
  </ApCallout>
</template>
