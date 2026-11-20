<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { ResolveBookingActions } from "@/features/resolutions/index.ts";
import { useRoute, type RouteLocationRaw } from "vue-router";
import { canAdministerOrganization, TakeoverHeader, useMissionScope, useSession } from "@/shell";
import type { ApiError } from "@/api";
import { ApButton, ApCallout, ApStationBar, OutcomeCallout, useNow } from "@/ui";
import { draftedByOther, editableStates, type Acknowledgement } from "./api.ts";
import DayNav from "./DayNav.vue";
import DemandPanel from "./DemandPanel.vue";
import FocusPanel from "./FocusPanel.vue";
import OfferClock from "./OfferClock.vue";
import { isBooking } from "./booking-state.ts";
import { offerClock } from "./offer-clock.ts";
import DraftGantt from "./DraftGantt.vue";
import { dayLabel, useSpacecraftNames } from "./names.ts";
import PlanFooter from "./PlanFooter.vue";
import { headerFor } from "./plan-header.ts";
import { historical } from "./plan-history.ts";
import PlanHistorySheet from "./PlanHistorySheet.vue";
import OldVersionCallout from "./OldVersionCallout.vue";
import { useBookingStopped } from "./useBookingStopped.ts";
import PlanStatePanel from "./PlanStatePanel.vue";
import { limitRefusal, overLimit } from "./start-limit.ts";
import StartLimits from "./StartLimits.vue";
import SelectedPanel from "./SelectedPanel.vue";
import { isPlanSuperseded, planErrorText } from "./errors.ts";
import SendBackSheet from "./SendBackSheet.vue";
import SubmitSheet from "./SubmitSheet.vue";
import PassResolutionsCallout from "./PassResolutionsCallout.vue";
import ProposalCallout from "./ProposalCallout.vue";
import { usePassResolutions } from "./usePassResolutions.ts";
import SupersededCallout from "./SupersededCallout.vue";
import PlanLifecycleCallouts from "./PlanLifecycleCallouts.vue";
import type { Expired } from "./lifecycle.ts";
import UnconfirmedCallout from "./UnconfirmedCallout.vue";
import { stationHits } from "./unavailable.ts";
import { planPrimary } from "./plan-primary.ts";
import { usePlanDay } from "./usePlanDay.ts";
import { resubmittedLines, sentBackLine } from "./review-lines.ts";
import type { ReviewAfter } from "./review-run.ts";
import { usePlanFocus } from "./usePlanFocus.ts";
import PlanReviewLine from "./PlanReviewLine.vue";

/** K1 · Plan a day (ScheduleFlow.md). States: plan-state.ts; data: usePlanDay. */
const route = useRoute();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const day = computed(() => {
  const q = route.query.day;
  return typeof q === "string" && /^\d{4}-\d{2}-\d{2}$/.test(q)
    ? q
    : new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
});
const focused = ref<string | null>(null);
/** U31: the day's pass-resolution conflicts (needs-you items), linked to their contacts. */
const resolutions = usePassResolutions(missionId, day);
const {
  view,
  proposal,
  busy,
  actionError,
  estimate,
  draftDay,
  resume,
  review,
  execute,
  edit,
  sendBack,
  alternatives,
  availability,
  refresh,
} = usePlanDay(missionId, day, focused);
const session = useSession();
const isAdmin = computed(() => canAdministerOrganization(session, scope.value.organization));
/** ux: someone else's draft names its drafter under the day picker; your own shows nothing. */
const draftedBy = computed(() =>
  view.value.kind === "plan" && view.value.plan.state === "draft"
    ? draftedByOther(view.value.plan, session.user.id)
    : null,
);
const sheet = ref<InstanceType<typeof SubmitSheet> | null>(null);
const sheetError = ref<ApiError | null>(null);
/** U61: passes an approval left out because their booking window had closed (until the day changes). */
const expired = ref<Expired | null>(null);
watch(day, () => (expired.value = null));
/** U26: drafted passes inside station outage/maintenance (blocking) or degraded (at risk) windows. */
const hits = computed(() =>
  view.value.kind === "plan"
    ? stationHits(view.value.plan, availability.value)
    : { blocking: [], atRisk: [] },
);
/** U20: an interrupted execution's callout and how many requests are left. */
const stopped = useBookingStopped(
  missionId,
  computed(() => (view.value.kind === "plan" ? view.value.plan : null)),
);
/** U73: `?version=N` of an older version is read-only (the latest version's number, else null). */
const latest = computed(() => (view.value.kind === "plan" ? historical(view.value.plan) : null));
const historySheet = ref<InstanceType<typeof PlanHistorySheet> | null>(null);
/** #257 (U97): the last review's result for a plan (its line, A6 disable on its version, kept note). */
const reviewed = ref<(ReviewAfter & Readonly<{ planId: string }>) | null>(null);
const current = computed(() =>
  reviewed.value && view.value.kind === "plan" && reviewed.value.planId === view.value.plan.id
    ? reviewed.value
    : null,
);
const refusedBecause = computed(() =>
  view.value.kind === "plan" && current.value?.version === view.value.plan.version
    ? current.value.because
    : null,
);
const primary = computed(() =>
  view.value.kind === "plan" && latest.value === null
    ? planPrimary(view.value.plan, isAdmin.value, {
        userId: session.user.id,
        refusedBecause: refusedBecause.value,
      })
    : null,
);

const sendBackSheet = ref<InstanceType<typeof SendBackSheet> | null>(null);
const sendBackError = ref<ApiError | null>(null);
async function onSendBack(reason: string) {
  if (view.value.kind !== "plan") return;
  const result = await sendBack(view.value.plan, reason);
  if (result.ok) {
    sendBackSheet.value?.close();
    focusSoon.to(() => reviewLine.value?.box ?? null);
  } else sendBackError.value = result.error;
}
const resubmitted = computed(() =>
  view.value.kind === "plan" ? resubmittedLines(view.value.plan) : null,
);
const sentBack = computed(() =>
  view.value.kind === "plan" ? sentBackLine(view.value.plan, session.user.id, isAdmin.value) : null,
);

/** #244 (A5, B4): focus follows Submit and Send back to their result lines (usePlanFocus.ts). */
const resultBox = ref<HTMLElement | null>(null);
const reviewLine = ref<InstanceType<typeof PlanReviewLine> | null>(null);
const unconfirmed = ref<InstanceType<typeof UnconfirmedCallout> | null>(null);
const focusSoon = usePlanFocus(() =>
  view.value.kind === "plan"
    ? `${view.value.plan.id}:${view.value.plan.version}:${view.value.plan.state}`
    : null,
);
watch(day, () => {
  reviewed.value = null;
  focusSoon.cancel();
});
async function onSubmit(acks: Acknowledgement[], note?: string) {
  if (view.value.kind !== "plan" || primary.value?.kind !== "sheet") return;
  const planId = view.value.plan.id;
  const out = await review(primary.value.act, view.value.plan, acks, note, session.user.id);
  if (out.kind === "refused") {
    // A draft superseded meanwhile (409 plan_superseded): the plan was re-read, so it lands in the
    // superseded state, which says nothing was submitted.
    if (isPlanSuperseded(out.error)) sheet.value?.close();
    else sheetError.value = out.error;
    return;
  }
  sheet.value?.close();
  reviewed.value = { ...out, planId };
  expired.value = out.expired;
  focusSoon.to(() => resultBox.value);
}
const editable = computed(
  () =>
    view.value.kind === "plan" &&
    latest.value === null &&
    editableStates.includes(view.value.plan.state),
);
function onEdit(change: { add?: string[]; remove?: string[] }) {
  if (view.value.kind !== "plan") return;
  // #244 (A5): the selection stays, so SelectedPanel swaps Remove ↔ Add in place (it moves focus
  // to the new button if focus was lost) instead of unmounting the focused one.
  void edit(view.value.plan, change);
}
const actionText = computed(() =>
  actionError.value ? (limitRefusal(actionError.value) ?? planErrorText(actionError.value)) : null,
);
/** U52: over the limit, Start is disabled with the sentence StartLimits shows above it. */
const overReason = computed(() => overLimit(estimate.value));
function onExecute() {
  if (view.value.kind === "plan") void execute(view.value.plan.id);
}
const nameOf = useSpacecraftNames(missionId);
const selected = ref<string | null>(null);

const STEPS = ["Demand", "Opportunities", "Draft", "Reserve"];
/** qa #52: a plan that has gone out for booking is at 04 Reserve. */
const step = computed(() =>
  view.value.kind === "drafting"
    ? 2
    : view.value.kind === "plan"
      ? isBooking(view.value.plan.state)
        ? 3
        : 2
      : 0,
);
const headerLine = computed(() => headerFor(view.value, dayLabel(day.value)));
const setupLink = computed((): RouteLocationRaw => ({ name: "setup.contact-planning" }));
/** ux: "NEXT OFFER EXPIRES T−… · KSAT" from the plan's provider_freeze (domain c38bb5de). */
const clockNow = useNow();
const clock = computed(() =>
  view.value.kind === "plan" ? offerClock(view.value.plan, nameOf, clockNow.value) : null,
);
</script>

<template>
  <TakeoverHeader
    :title="`Plan ${dayLabel(day)}`"
    :context="headerLine"
    :close="{ name: 'ops.contacts' }"
    close-label="Close plan"
    title-as="h1"
  >
    <template #steps><ApStationBar :steps="STEPS" :current="step" label="Plan steps" /></template>
    <template v-if="clock" #clocks
      ><OfferClock :clock="clock" @select="selected = $event"
    /></template>
    <template v-if="view.kind === 'plan'" #actions
      ><ApButton variant="ghost" size="compact" @click="historySheet?.open()"
        >History</ApButton
      ></template
    >
  </TakeoverHeader>
  <DayNav :day="day" :show-strip="view.kind !== 'not_set_up'" />
  <p v-if="draftedBy" class="m-0 font-mono text-sm text-text-3">{{ draftedBy }}</p>
  <PassResolutionsCallout :passes="resolutions" />
  <ProposalCallout v-if="proposal" :mission-id="missionId" :proposal="proposal" />
  <template v-if="view.kind === 'plan'">
    <PlanLifecycleCallouts :day="day" :superseded-by="view.plan.superseded_by" :expired="expired" />
    <OldVersionCallout v-if="latest !== null" :plan="view.plan" :latest="latest" />
    <SupersededCallout v-else-if="view.plan.superseded" :superseded="view.plan.superseded" />
    <PlanReviewLine
      v-else-if="sentBack || resubmitted"
      ref="reviewLine"
      :sent-back="sentBack"
      :resubmitted="resubmitted"
      @history="historySheet?.open()"
    />
    <ApCallout v-else-if="stopped" :tone="stopped.tone">{{ stopped.text }}</ApCallout>
    <!-- U30: on any state that has unconfirmed bookings, on top of the state's own callout. -->
    <UnconfirmedCallout
      v-if="view.plan.unconfirmed"
      ref="unconfirmed"
      :plan="view.plan"
      :name-of="nameOf"
      :member-note="!isAdmin"
    >
      <!-- U32 (fe-setup's resolutions): org admins resolve each pass; the plan refetches after. -->
      <template v-if="isAdmin && latest === null" #row-actions="{ pass }">
        <ResolveBookingActions
          :mission-id="missionId"
          :plan-id="view.plan.id"
          :pass="pass"
          @resolved="(unconfirmed?.armFocus(), refresh())"
        />
      </template>
    </UnconfirmedCallout>
    <!-- An older server without the unconfirmed block: no counts, no guess. -->
    <ApCallout v-else-if="view.plan.state === 'unconfirmed'" tone="caution">
      The provider hasn't confirmed some bookings within the confirmation window. They may or may
      not be booked, so Cadence won't send them again. Check them with the provider.
    </ApCallout>
    <div
      class="grid min-h-0 flex-1 grid-cols-1 gap-3 console:grid-cols-[300px_minmax(0,1fr)_340px]"
    >
      <DemandPanel
        :plan="view.plan"
        :day="day"
        :name-of="nameOf"
        :focused="focused"
        @focus="focused = focused === $event ? null : $event"
      />
      <div class="flex min-h-0 flex-col gap-3">
        <DraftGantt
          :plan="view.plan"
          :day="day"
          :name-of="nameOf"
          :focused="focused"
          :selected="selected"
          :alternatives="alternatives"
          :availability="availability"
          :muted="view.plan.superseded !== null"
          :title="isBooking(view.plan.state) ? 'Plan · by station' : undefined"
          class="min-h-0 flex-1"
          @select="selected = $event"
        />
        <FocusPanel
          :plan="view.plan"
          :day="day"
          :focused="focused"
          :selected="selected"
          :name-of="nameOf"
          :muted="view.plan.superseded !== null"
          @select="selected = $event"
        />
      </div>
      <SelectedPanel
        :plan="view.plan"
        :selected="selected"
        :focused="focused"
        :alternatives="alternatives"
        :name-of="nameOf"
        :editable="editable"
        :busy="busy"
        @add="onEdit({ add: [$event] })"
        @remove="onEdit({ remove: [$event] })"
        :hits="hits"
        @focus="focused = $event"
        @select="selected = $event"
      />
    </div>
    <ApCallout v-if="actionText" tone="caution" role="alert">{{ actionText }}</ApCallout>
    <div v-if="current" ref="resultBox" tabindex="-1">
      <OutcomeCallout :outcome="current" />
    </div>
    <PlanFooter
      :plan="view.plan"
      :is-admin="isAdmin"
      :busy="busy"
      :open-repair-run="
        proposal?.repair_of?.plan.id === view.plan.id ? proposal.repair_of.run_id : null
      "
      :requests-left="stopped?.left ?? null"
      :can-send-back="isAdmin && latest === null && view.plan.state === 'pending_approval'"
      :read-only="latest !== null"
      :user-id="session.user.id"
      :refused-because="refusedBecause"
      @send-back="sendBackSheet?.open()"
      @sheet="sheet?.open()"
      @redraft="draftDay"
      @execute="onExecute"
    />
    <SendBackSheet
      v-if="isAdmin && latest === null && view.plan.state === 'pending_approval'"
      ref="sendBackSheet"
      v-model:error="sendBackError"
      :author="view.plan.author?.name ?? null"
      :busy="busy"
      @submit="onSendBack"
    />
    <SubmitSheet
      v-if="primary?.kind === 'sheet'"
      ref="sheet"
      v-model:error="sheetError"
      :plan="view.plan"
      :name-of="nameOf"
      :commit-label="primary.label"
      :title="primary.title"
      :confirm="primary.confirm"
      :act="primary.act"
      :user-id="session.user.id"
      :kept-note="current?.keepNote ?? null"
      :busy="busy"
      :day="day"
      @submit="onSubmit"
    />
    <PlanHistorySheet
      ref="historySheet"
      :mission-id="missionId"
      :plan-id="view.plan.id"
      :day="day"
    />
  </template>
  <template v-else>
    <PlanStatePanel :view="view" />
    <StartLimits :estimate="estimate" :error="actionError" />
    <ApCallout v-if="actionText && !limitRefusal(actionError)" tone="caution" role="alert">{{
      actionText
    }}</ApCallout>
    <footer class="flex flex-none justify-end border-t border-hairline pt-3">
      <ApButton v-if="view.kind === 'not_set_up'" variant="primary" size="commit" :to="setupLink"
        >Set up contact planning</ApButton
      >
      <ApButton
        v-else-if="view.kind === 'no_draft' || view.kind === 'draft_failed'"
        variant="primary"
        size="commit"
        :disabled="busy || overReason !== null"
        :disabled-reason="overReason ?? 'Drafting…'"
        @click="draftDay"
        >Draft the day</ApButton
      >
      <ApButton
        v-else-if="view.kind === 'interrupted'"
        variant="primary"
        size="commit"
        :disabled="busy"
        disabled-reason="Working…"
        @click="resume"
        >Continue drafting</ApButton
      >
    </footer>
  </template>
</template>
