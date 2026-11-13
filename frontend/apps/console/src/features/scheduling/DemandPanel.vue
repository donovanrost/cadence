<script setup lang="ts">
import { computed } from "vue";
import { ApListRow, ApPanel, useNow } from "@/ui";
import { reasonText, type PlanDetail } from "./api.ts";
import BookingIssues from "./BookingIssues.vue";
import { isBooking, rejectedRows } from "./booking-state.ts";
import { expiredRows } from "./offer-clock.ts";
import { contactsShortText, coverage } from "./coverage.ts";
import { gapSentence } from "./focus-day.ts";
import type { SpacecraftName } from "./names.ts";

/** A · Demand: only spacecraft whose rule isn't met (ScheduleFlow R01: start from demand). */
const props = defineProps<{
  plan: PlanDetail;
  nameOf: (id: string | null) => SpacecraftName | null;
  focused: string | null;
  /** The plan's UTC day (YYYY-MM-DD), for the #74 gap sentence's date prefix. */
  day: string;
}>();
defineEmits<{ focus: [spacecraftId: string] }>();

const unmet = computed(() => props.plan.demand.spacecraft.filter((s) => !s.rule_met));
/** Rejected or failed bookings and expired offers lead the list (ScheduleFlow K1: rejections become A rows). */
const now = useNow();
/** Expired unsent offers lead too (ux: they can't be booked; re-plan to replace them). */
const rejected = computed(() => [
  ...rejectedRows(props.plan.passes),
  ...expiredRows(props.plan, now.value),
]);
const ruleText = computed(() =>
  [...new Set(props.plan.demand.rules.map((r) => r.text))].slice(0, 2),
);
/** Server causes: the demand row's reasons plus its unmet requirements' specific `why` codes. */
function causes(spacecraftId: string, reasons: readonly string[]): string[] {
  const fromUnmet = props.plan.unmet
    .filter((u) => u.spacecraft_id === spacecraftId)
    .flatMap((u) => u.why);
  return [...new Set([...fromUnmet, ...reasons])];
}
type DemandRow = PlanDetail["demand"]["spacecraft"][number];
/** #74 (ux): a gap over the limit reads as the sentence with its span and the limit. */
function words(code: string, row: DemandRow): string {
  return (
    (code === "max_gap_exceeded" ? gapSentence(row.longest_gap, props.day) : null) ??
    reasonText(code)
  );
}
function why(reasons: readonly string[], row: DemandRow): string {
  if (row.contacts.have === 0 && reasons.length > 0)
    return `No window can cover it: ${reasonText(reasons[0] ?? "").toLowerCase()}`;
  return reasons.length > 0 ? reasons.map((r) => words(r, row)).join(" · ") : "Rule not met";
}
/** U28/#28: requirements an admin accepted as gaps, with the reason (api 97523716). */
const accepted = computed(
  () => new Map((props.plan.approval?.exceptions ?? []).map((e) => [e.requirement_id, e.reason])),
);
/** `Gap accepted · <reason>` for a spacecraft whose unmet requirements were all accepted. */
function acceptedText(spacecraftId: string): string | null {
  const reqs = props.plan.unmet.filter((u) => u.spacecraft_id === spacecraftId);
  if (reqs.length === 0 || !reqs.every((u) => accepted.value.has(u.requirement_id))) return null;
  const reasons = [...new Set(reqs.map((u) => accepted.value.get(u.requirement_id) ?? ""))];
  // U29: name who accepted it (the approval's actor records the acknowledgements).
  const by = props.plan.approval?.actor.name;
  return `Gap accepted${by ? ` by ${by}` : ""} · ${reasons.join(" · ")}`;
}
const booking = computed(() => isBooking(props.plan.state));
const meta = computed(() => {
  const c = coverage(props.plan);
  const lost = rejected.value.length;
  // qa #52: after booking, coverage is the draft's; lost or rejected bookings come first.
  if (lost > 0) return `${lost} ${lost === 1 ? "pass" : "passes"} not booked`;
  return c.spacecraft > 0
    ? `${c.spacecraft} spacecraft · ${contactsShortText(c.contactsShort)}`
    : booking.value
      ? "All spacecraft covered as drafted"
      : "All spacecraft covered";
});
</script>

<template>
  <ApPanel index="A" title="Demand" :meta="meta" pane flush>
    <BookingIssues
      :rows="rejected"
      :plan-id="plan.id"
      :name-of="nameOf"
      @focus="$emit('focus', $event)"
    />
    <ul v-if="unmet.length > 0" class="m-0 list-none p-0">
      <ApListRow
        v-for="row in unmet"
        :key="row.spacecraft_id"
        :state="row.contacts.have === 0 ? 'crit' : 'caution'"
        :sentence="
          acceptedText(row.spacecraft_id) ?? why(causes(row.spacecraft_id, row.reasons), row)
        "
        :meta="`${row.contacts.have} / ${row.contacts.need ?? '?'} contacts`"
      >
        <template #title>
          <button
            type="button"
            class="max-md:hit-44 cursor-pointer border-0 bg-transparent p-0 text-left font-mono text-base font-semibold text-readout hover:underline"
            :aria-pressed="focused === row.spacecraft_id"
            @click="$emit('focus', row.spacecraft_id)"
          >
            {{ nameOf(row.spacecraft_id)?.name ?? row.spacecraft_id }}
          </button>
        </template>
      </ApListRow>
    </ul>
    <p v-else class="m-0 px-4 py-3 text-md text-text-3">
      {{
        booking
          ? "Every spacecraft met its rule when the plan was drafted."
          : "Every spacecraft meets its rule in this draft."
      }}
    </p>
    <p
      v-for="text in ruleText"
      :key="text"
      class="m-0 border-t border-hairline px-4 py-2.5 font-mono text-xs text-text-4 uppercase"
    >
      From requirement: {{ text }}
    </p>
  </ApPanel>
</template>
