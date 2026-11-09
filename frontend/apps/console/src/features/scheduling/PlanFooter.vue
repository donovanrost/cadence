<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApStatStrip, ApStatTile } from "@/ui";
import type { PlanDetail } from "./api.ts";

/**
 * K1 footer: totals + the one primary. Submit waits for S5 on the server, so a ready draft's
 * primary is disabled with that reason; conflicts block with their own reason (#28).
 */
const props = defineProps<{ plan: PlanDetail }>();

const conflicts = computed(() => props.plan.conflicts.length);
const unmet = computed(() => props.plan.unmet.length);
const primary = computed(() => {
  if (props.plan.state !== "draft") return null;
  if (conflicts.value > 0)
    return {
      label: "Submit",
      reason: `${conflicts.value} conflicts. Move or remove a pass to submit.`,
    };
  const label =
    unmet.value > 0
      ? `Accept ${unmet.value} gaps and submit`
      : `Submit ${props.plan.counts.passes} requests`;
  return { label, reason: "Submitting from the console arrives with the next server update." };
});
</script>

<template>
  <footer class="flex flex-none flex-wrap items-stretch gap-3 border-t border-hairline pt-3">
    <ApStatStrip :columns="4" label="Plan totals" class="min-w-[min(100%,520px)] flex-1">
      <ApStatTile label="Passes" :value="plan.counts.passes" />
      <ApStatTile label="Minutes" :value="plan.counts.minutes" />
      <ApStatTile
        label="Rule met"
        :value="plan.demand.rule_met"
        :denominator="plan.demand.rule_total"
        :state="plan.demand.rule_met < plan.demand.rule_total ? 'caution' : 'nominal'"
      />
      <ApStatTile
        label="Conflicts"
        :value="conflicts"
        :state="conflicts > 0 ? 'crit' : 'neutral'"
      />
    </ApStatStrip>
    <div v-if="primary" class="flex min-w-[240px] flex-col justify-center gap-1.5">
      <ApButton variant="primary" size="commit" disabled :disabled-reason="primary.reason">{{
        primary.label
      }}</ApButton>
      <p class="m-0 max-w-[320px] text-sm text-text-3">{{ primary.reason }}</p>
    </div>
  </footer>
</template>
