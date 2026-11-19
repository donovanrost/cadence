<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApStatStrip, ApStatTile } from "@/ui";
import type { PlanDetail } from "./api.ts";
import { isBooking, rejectedRows } from "./booking-state.ts";
import { planPrimary } from "./plan-primary.ts";
import type { Because } from "./review-words.ts";

/**
 * K1 footer: totals + the one primary for the plan's state (plan-primary.ts). Conflicts include the
 * server's station_unavailable entries; at-risk (station_degraded) is the caption (U26).
 */
const props = defineProps<{
  plan: PlanDetail;
  isAdmin: boolean;
  busy: boolean;
  /** Replaces the sheet primary's label (K2: "Apply r42 · book N passes"). */
  sheetLabel?: string | undefined;
  /** Replaces the redraft primary's label (K2 superseded proposal: "Propose again"). */
  redraftLabel?: string | undefined;
  /** U28: the open K2 proposal's run for this plan; the re-plan link opens it instead of a new one. */
  openRepairRun?: string | null | undefined;
  /** bookingStopped's `left` on an interrupted plan (0 hides Continue booking). */
  requestsLeft?: number | null | undefined;
  /** Admin reviewing a pending_approval plan: a secondary Send back beside Approve. */
  canSendBack?: boolean | undefined;
  /** U73: an older version (`?version=N`) shows its totals but no actions. */
  readOnly?: boolean | undefined;
  /** U97 (#257): the viewer (the submitter's own plan) and a self-approval refusal on this version. */
  userId?: string | null | undefined;
  refusedBecause?: Because | null | undefined;
}>();
defineEmits<{ sheet: []; execute: []; redraft: []; sendBack: [] }>();
const primary = computed(() =>
  planPrimary(props.plan, props.isAdmin, {
    openRepairRun: props.openRepairRun ?? null,
    requestsLeft: props.requestsLeft ?? null,
    userId: props.userId ?? null,
    refusedBecause: props.refusedBecause ?? null,
  }),
);
const conflicts = computed(() => props.plan.conflicts.length);
const booking = computed(() => isBooking(props.plan.state));
const lost = computed(() => rejectedRows(props.plan.passes).length);
const atRisk = computed(() => props.plan.at_risk.flatMap((r) => r.snapshot_ids).length);
</script>

<template>
  <footer class="flex flex-none flex-wrap items-stretch gap-3 border-t border-hairline pt-3">
    <ApStatStrip :columns="4" label="Plan totals" class="min-w-[min(100%,520px)] flex-1">
      <ApStatTile label="Passes" :value="plan.counts.passes" />
      <ApStatTile label="Minutes" :value="plan.counts.minutes" />
      <!-- qa #52: once booking, the rule figure is the draft's; lost bookings say so beside it. -->
      <ApStatTile
        :label="booking ? 'Rule met as drafted' : 'Rule met'"
        :value="plan.demand.rule_met"
        :denominator="plan.demand.rule_total"
        unit="spacecraft"
        :state="plan.demand.rule_met < plan.demand.rule_total || lost > 0 ? 'caution' : 'nominal'"
        :caption="lost > 0 ? `${lost} ${lost === 1 ? 'pass' : 'passes'} not booked` : undefined"
        :caption-state="lost > 0 ? 'caution' : undefined"
      />
      <ApStatTile
        label="Conflicts"
        :value="conflicts"
        :state="conflicts > 0 ? 'crit' : 'neutral'"
        :caption="atRisk > 0 ? `${atRisk} at risk` : undefined"
        :caption-state="atRisk > 0 ? 'caution' : undefined"
      />
    </ApStatStrip>
    <div v-if="!readOnly" class="flex min-w-[240px] flex-col justify-center gap-1.5">
      <template v-if="primary.kind === 'sheet'">
        <ApButton variant="primary" size="commit" :disabled="busy" @click="$emit('sheet')">{{
          sheetLabel ?? primary.label
        }}</ApButton>
        <p v-if="primary.note" class="m-0 max-w-[320px] text-sm text-text-3">{{ primary.note }}</p>
      </template>
      <ApButton
        v-else-if="primary.kind === 'execute'"
        variant="primary"
        size="commit"
        :disabled="busy"
        @click="$emit('execute')"
        >{{ primary.label }}</ApButton
      >
      <ApButton
        v-else-if="primary.kind === 'redraft'"
        variant="primary"
        size="commit"
        :disabled="busy"
        @click="$emit('redraft')"
        >{{ redraftLabel ?? primary.label }}</ApButton
      >
      <ApButton
        v-else-if="primary.kind === 'link'"
        variant="primary"
        size="commit"
        :to="primary.to"
        >{{ primary.label }}</ApButton
      >
      <template v-else-if="primary.kind === 'blocked'">
        <ApButton variant="primary" size="commit" disabled :disabled-reason="primary.reason">{{
          primary.label
        }}</ApButton>
        <p class="m-0 max-w-[320px] text-sm text-text-3">{{ primary.reason }}</p>
      </template>
      <p v-else-if="primary.note" class="m-0 max-w-[320px] text-md text-text-3">
        {{ primary.note }}
      </p>
      <!-- U97: Send back stays when Approve is hidden (the submitter) or disabled (a self refusal). -->
      <ApButton v-if="canSendBack" variant="ghost" :disabled="busy" @click="$emit('sendBack')"
        >Send back…</ApButton
      >
    </div>
  </footer>
</template>
