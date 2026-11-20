<script setup lang="ts">
import { computed } from "vue";
import { ApStatTile, formatCount } from "@/ui";
import type { Actor } from "@/api";
import { authorsLine, readinessAfterLine, routesDelta, type Outcome } from "./outcome.ts";

/**
 * K3's tiles (Changes.md K3; ca-ux's words for #522): Changes · SC · Routes, then the readiness
 * line. SC is the fleet after applying; Routes is added − removed. Without an outcome (not computed
 * yet, or the server can't), the Changes tile alone.
 */
const props = defineProps<{
  staged: number;
  outcome: Outcome | null;
  authors: readonly Actor[];
  viewerId: string | null;
}>();
const authorsText = computed(() => authorsLine(props.authors, props.viewerId));
const tiles = computed(() => {
  const o = props.outcome;
  return [
    { label: "Changes", value: formatCount(props.staged) },
    ...(o?.spacecraft ? [{ label: "SC", value: formatCount(o.spacecraft.after) }] : []),
    ...(o?.routes ? [{ label: "Routes", value: routesDelta(o.routes) }] : []),
  ];
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <div
      class="grid gap-px border border-hairline bg-hairline"
      :class="
        tiles.length === 3 ? 'grid-cols-3' : tiles.length === 2 ? 'grid-cols-2' : 'grid-cols-1'
      "
    >
      <ApStatTile v-for="t in tiles" :key="t.label" :label="t.label" :value="t.value" />
    </div>
    <p v-if="outcome?.readiness" data-readiness-after class="m-0 text-sm text-text-2">
      {{ readinessAfterLine(outcome.readiness) }}
    </p>
    <p v-if="authorsText" data-authors class="m-0 text-sm text-text-3">{{ authorsText }}</p>
  </div>
</template>
