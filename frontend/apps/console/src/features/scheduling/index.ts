/**
 * Public API of scheduling (lead, K0/K1): the contact state model, the plan/draft/repair contracts,
 * and the plan pieces Re-plan (features/replan, fe-setup) reuses. Import only from here.
 */
export {
  contactOpState,
  contactState,
  contactStateWord,
  sourceLabel,
  type ContactState,
} from "./contact.ts";
export { bookingStopped, type BookingStopped } from "./booking.ts";
export { useBookingStopped } from "./useBookingStopped.ts";
export { default as UnconfirmedCallout } from "./UnconfirmedCallout.vue";
export { shortWhen, unconfirmedView, type UnconfirmedPass } from "./unconfirmed.ts";
export {
  byAuthor,
  continueDraft,
  executePlan,
  fetchAvailability,
  fetchPlan,
  fetchPlans,
  fetchRepair,
  reasonText,
  repairableStates,
  startRepair,
  stationCode,
  stationKey,
  stationName,
  submitPlan,
  approvePlan,
  type Acknowledgement,
  type Availability,
  type AvailabilityWindow,
  type PlanDetail,
  planStates,
  type PlanState,
  type Repair,
  type StationRef,
} from "./api.ts";
export { contactsShortText, coverage, gapGroups, spacecraftNotCovered } from "./coverage.ts";
export { dayLabel, useSpacecraftNames, type SpacecraftName } from "./names.ts";
export { planErrorText } from "./errors.ts";
export type { RepairInfo } from "./repair-info.ts";
export { planHeaderTail, planPrimary, type PlanPrimary } from "./plan-primary.ts";
export type { PlanView } from "./plan-state.ts";
export { default as DraftGantt } from "./DraftGantt.vue";
export { default as PlanFooter } from "./PlanFooter.vue";
export { default as PlanStatePanel } from "./PlanStatePanel.vue";
export { default as SubmitSheet } from "./SubmitSheet.vue";
