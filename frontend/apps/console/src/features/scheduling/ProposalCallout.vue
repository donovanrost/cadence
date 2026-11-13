<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import type { RouteLocationRaw } from "vue-router";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { ApCallout, plural } from "@/ui";
import { byAuthor, fetchRepair, stationCode, type PlanSummary } from "./api.ts";

/**
 * U28: K1 never opens a repair proposal; it says one is open for the day and links to K2, which
 * owns applying it. The move summary comes from the repair run (absent until it loads).
 */
const props = defineProps<{
  missionId: MissionId;
  proposal: PlanSummary;
}>();
const repairOf = computed(() => props.proposal.repair_of);
const repair = useRemoteQuery(
  () => repairOf.value?.run_id ?? null,
  (runId, signal) => fetchRepair(props.missionId, runId, signal),
);
const moves = computed(() => {
  const r = repair.state.value;
  if (r.status !== "ready" || !r.value.diff) return null;
  const { moved, dropped } = r.value.diff;
  const off = [
    ...new Set([...moved.map((m) => m.from), ...dropped].map((p) => stationCode(p.station))),
  ];
  const parts = [
    moved.length > 0 ? `${plural(moved.length, "pass", "passes")} move` : null,
    dropped.length > 0 ? `${plural(dropped.length, "pass", "passes")} dropped` : null,
  ].filter((x) => x !== null);
  if (parts.length === 0) return null;
  return `${parts.join(", ")}${off.length > 0 ? ` off ${off.join(", ")}` : ""}`;
});
const proposed = computed(() => {
  return `proposed ${props.proposal.updated_at.slice(11, 16)}Z${byAuthor(props.proposal.author)}`;
});
const to = computed((): RouteLocationRaw | null =>
  repairOf.value
    ? {
        name: "ops.contacts.replan",
        query: { plan: repairOf.value.plan.id, run: repairOf.value.run_id },
      }
    : null,
);
</script>

<template>
  <ApCallout v-if="to" tone="info">
    <span class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
      <span
        >A re-plan proposal is open for this day{{ moves ? `: ${moves}` : "" }} ·
        {{ proposed }}</span
      >
      <RouterLink :to="to" class="max-md:hit-44 font-mono text-sm text-readout"
        >Open in Re-plan →</RouterLink
      >
    </span>
  </ApCallout>
</template>
