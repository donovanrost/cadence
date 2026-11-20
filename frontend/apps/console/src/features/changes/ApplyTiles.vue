<script setup lang="ts">
import { computed } from "vue";
import { ApStatTile, formatCount } from "@/ui";
import type { Actor } from "@/api";
import { authorsLine, readinessAfterLine, routesDelta, type Outcome } from "./outcome.ts";

/**
 * K3's tiles (Changes.md K3; ca-ux's words for #522, ux 11-20): Changes · Spacecraft · Routes (never
 * "SC", U102), then the readiness line.
 * - `outcome` absent (a server before #522, or checks not back yet): the Changes tile alone; the
 *   server hasn't said anything, so nothing is claimed.
 * - `outcome: null` (the pipeline didn't fully check the set, or a read failed): the tiles stay as
 *   "Spacecraft —" and "Routes —", with the muted line in place of the readiness line (ux: never
 *   drop the tiles silently).
 * - `readiness: null` alone (the set touches nothing readiness reads): no readiness line.
 */
const props = defineProps<{
  staged: number;
  outcome: Outcome | null | undefined;
  authors: readonly Actor[];
  viewerId: string | null;
}>();
const NOT_WORKED_OUT =
  "Cadence couldn't work out these changes' effect on the fleet and its readiness. The checks still run.";
const authorsText = computed(() => authorsLine(props.authors, props.viewerId));
type Tile = Readonly<{ label: string; value: string | null }>;
const tiles = computed((): readonly Tile[] => {
  const o = props.outcome;
  const changes: Tile = { label: "Changes", value: formatCount(props.staged) };
  if (o === undefined) return [changes];
  if (o === null)
    return [changes, { label: "Spacecraft", value: null }, { label: "Routes", value: null }];
  return [
    changes,
    ...(o.spacecraft ? [{ label: "Spacecraft", value: formatCount(o.spacecraft.after) }] : []),
    ...(o.routes ? [{ label: "Routes", value: routesDelta(o.routes) }] : []),
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
    <p v-else-if="outcome === null" data-not-worked-out class="m-0 text-sm text-text-3">
      {{ NOT_WORKED_OUT }}
    </p>
    <p v-if="authorsText" data-authors class="m-0 text-sm text-text-3">{{ authorsText }}</p>
  </div>
</template>
