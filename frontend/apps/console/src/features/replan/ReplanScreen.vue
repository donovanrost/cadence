<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery, type ApiError } from "@/api";
import { canAdministerOrganization, TakeoverHeader, useMissionScope, useSession } from "@/shell";
import { ApButton, ApCallout, ApPanel, ApRemote, ApStationBar, plural } from "@/ui";
import {
  DraftGantt,
  useBookingStopped,
  byAuthor,
  PlanFooter,
  PlanStatePanel,
  SubmitSheet,
  UnconfirmedCallout,
  coverage,
  planPrimary,
  repairableStates,
  spacecraftNotCovered,
  useSpacecraftNames,
  type Acknowledgement,
  type PlanDetail,
  type PlanView,
  fetchAvailability,
} from "@/features/scheduling/index.ts";
import ChangesPanel from "./ChangesPanel.vue";
import { replanErrorText } from "./errors.ts";
import { lostWindow } from "./impact.ts";
import { bookingRequests } from "./applied.ts";
import { useLostBookings } from "./useLostBookings.ts";
import ImpactPanel from "./ImpactPanel.vue";
import StationImpactPanel from "./StationImpactPanel.vue";
import { useStationEntry } from "./useStationEntry.ts";
import { useReplan } from "./useReplan.ts";

/** K2 v1 · Re-plan after provider changes (DECISIONS #25), entered from a plan (`?plan=`). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { planId, runId, source, repair, busy, actionError, propose, resume, apply, execute } =
  useReplan(missionId);
const nameOf = useSpacecraftNames(missionId);
// Station-down entry (S7): resolves the plan to repair into ?plan=, then the plan flow continues.
const station = useStationEntry(missionId);
const availability = useRemoteQuery(missionId, (id, signal) => fetchAvailability(id, signal));
const liveSource = computed(() => (source.value.status === "ready" ? source.value.value : null));
const lost = useLostBookings(missionId, liveSource);
/** Re-plan around what was lost (station outage window, else the lost bookings' span). */
function proposeAround() {
  const window = station.span.value ?? lostWindow(lost.impact.value?.rows ?? [], new Date());
  void propose(window ?? undefined);
}
const session = useSession();
const isAdmin = computed(() => canAdministerOrganization(session, scope.value.organization));
const sheet = ref<InstanceType<typeof SubmitSheet> | null>(null);
const sheetError = ref<ApiError | null>(null);
const STEPS = ["Impact", "Proposal", "Apply"];

/** The repair run as a K1 view for the shared state panel (drafting / interrupted / failed). */
const runView = computed<Exclude<PlanView, { kind: "plan" }> | null>(() => {
  const r = repair.value;
  if (!runId.value) return null;
  if (r.status === "loading") return { kind: "loading" };
  if (r.status === "failed") return { kind: "failed", error: r.error };
  const { run, plan, diff } = r.value;
  if (run.state === "queued" || run.state === "running")
    return { kind: "drafting", phase: run.phase, startedAt: run.started_at };
  if (run.state === "interrupted") return { kind: "interrupted", phase: run.phase };
  if (run.state === "failed" || run.state === "canceled")
    return { kind: "draft_failed", message: run.failure?.message ?? "The re-plan failed." };
  return plan && diff
    ? null
    : { kind: "draft_failed", message: "The re-plan finished without a proposal." };
});
const proposal = computed(() =>
  repair.value.status === "ready" && repair.value.value.plan && repair.value.value.diff
    ? repair.value.value
    : null,
);
/** The repair read embeds the proposal with its derived state (`interrupted` included, 5b49faeb). */
const footerPlan = computed(() => proposal.value?.plan ?? null);
/** Apply is the current step once the proposal has left draft / pending approval. */
const step = computed(() => {
  const state = footerPlan.value?.state;
  if (!state) return 0;
  return state === "draft" || state === "pending_approval" ? 1 : 2;
});
/** Booking requests Apply sends (U28): moves and adds; drops send nothing. */
const requests = computed(() => {
  const d = proposal.value?.diff;
  return d ? bookingRequests(d) : 0;
});
/** Interrupted booking: callout + whether anything is left to continue (ux 1a906155). */
const stopped = useBookingStopped(missionId, footerPlan);
const applyLabel = (plan: PlanDetail) =>
  !isAdmin.value
    ? "Request approval for the proposal"
    : coverage(plan).gaps > 0
      ? `Accept ${plural(coverage(plan).gaps, "gap")} and apply the proposal`
      : `Apply proposal · send ${plural(requests.value, "request")}`;
/** The sheet's confirm names what Apply sends (U28), not the plan's total passes. */
const applyConfirm = computed(() => {
  const kept = proposal.value?.diff?.kept.length ?? 0;
  return `This approves the proposal and sends ${plural(requests.value, "booking request")}. The ${plural(kept, "kept pass", "kept passes")} stay booked.`;
});
const primary = computed(() =>
  footerPlan.value
    ? planPrimary(footerPlan.value, isAdmin.value, { requestsLeft: stopped.value?.left ?? null })
    : null,
);
/** B1/B2 share one axis covering the repair window and every pass of both plans (moves can land after it). */
const span = computed(() => {
  const r = repair.value;
  if (r.status !== "ready") return undefined;
  const times = [Date.parse(r.value.run.horizon.from), Date.parse(r.value.run.horizon.to)];
  for (const p of [...(liveSource.value?.passes ?? []), ...(r.value.plan?.passes ?? [])])
    times.push(Date.parse(p.starts_at), Date.parse(p.ends_at));
  return { from: Math.min(...times), to: Math.max(...times) };
});
/** U28: once proposed, the header says what it repairs and how much moves. */
const changeWords = computed(() => {
  const d = proposal.value?.diff;
  if (!d) return "";
  return (
    [
      d.moved.length > 0 ? plural(d.moved.length, "move") : null,
      d.dropped.length > 0 ? `${d.dropped.length} dropped` : null,
      d.added.length > 0 ? `${d.added.length} added` : null,
    ]
      .filter(Boolean)
      .join(" · ") || "no changes"
  );
});
const stationTitle = computed(() => {
  const a = station.availability.value;
  const state = a.status === "ready" ? a.value.status.state : null;
  const name = station.stationName.value;
  return state === "down" ? `${name} outage` : state === "degraded" ? `${name} degraded` : name;
});
const context = computed(() => {
  const s = source.value;
  if (s.status !== "ready") return "Re-plan";
  const state = s.value.state.replaceAll("_", " ");
  if (!proposal.value) return `Re-plan · live plan r${s.value.version} · ${state}`;
  const started = repair.value.status === "ready" ? repair.value.value.run.started_at : null;
  const proposed = started
    ? `proposed ${started.slice(11, 16)}Z${byAuthor(proposal.value.plan?.author ?? null)}`
    : null;
  return [
    `Repair of r${s.value.version} (${state})`,
    proposed,
    station.stationId.value ? stationTitle.value : null,
  ]
    .filter(Boolean)
    .join(" · ");
});
const title = computed(() => {
  const s = source.value;
  if (proposal.value && s.status === "ready")
    return `r${s.value.version} → proposal · ${changeWords.value}`;
  return station.stationId.value ? stationTitle.value : "Re-plan after provider changes";
});
async function onApply(acks: Acknowledgement[]) {
  const plan = proposal.value?.plan;
  if (!plan) return;
  const result = await apply(plan, acks);
  if (result.ok) sheet.value?.close();
  else sheetError.value = result.error;
}
</script>

<template>
  <TakeoverHeader
    :title="title"
    :context="context"
    :close="{ name: 'ops.contacts' }"
    close-label="Close re-plan"
    title-as="h1"
  >
    <template #steps
      ><ApStationBar :steps="STEPS" :current="step" label="Re-plan steps"
    /></template>
  </TakeoverHeader>
  <template v-if="!planId && station.stationId.value">
    <ApRemote :state="station.availability.value" loading-label="Loading station status…">
      <template #default="{ value: avail }">
        <StationImpactPanel
          :mission-id="missionId"
          :station-id="station.stationId.value"
          :station-name="station.stationName.value"
          :availability="avail"
        />
        <ApCallout v-if="station.resolved.value === 'none'" tone="info"
          >No plan has bookings at this station in the outage window, booked or lost, so there's
          nothing to re-plan.</ApCallout
        >
      </template>
    </ApRemote>
  </template>
  <ApPanel v-else-if="!planId" index="A" title="Impact">
    <ApCallout tone="info"
      >Open a re-plan from a contact plan that has rejected or failed bookings, or from a station
      that's down.</ApCallout
    >
  </ApPanel>
  <ApRemote v-else :state="source" loading-label="Loading the live plan…">
    <template #default="{ value: live }">
      <PlanStatePanel v-if="runView" :view="runView" />
      <template v-else-if="proposal && proposal.plan && proposal.diff">
        <ApCallout v-if="stopped" :tone="stopped.tone">{{ stopped.text }}</ApCallout>
        <UnconfirmedCallout :plan="footerPlan ?? proposal.plan" :name-of="nameOf" />
        <div
          class="grid min-h-0 flex-1 grid-cols-1 gap-3 console:grid-cols-[300px_minmax(0,1fr)_360px]"
        >
          <StationImpactPanel
            v-if="station.stationId.value && station.availability.value.status === 'ready'"
            :mission-id="missionId"
            :station-id="station.stationId.value"
            :station-name="station.stationName.value"
            :availability="station.availability.value.value"
          />
          <ImpactPanel
            v-else
            :live="live"
            :state="lost.state.value"
            :impact="lost.impact.value"
            :has-window="lost.hasWindow.value"
            @retry="lost.refetch"
          />
          <div class="flex min-h-0 flex-col gap-3">
            <DraftGantt
              :plan="live"
              day=""
              :span="span"
              index="B1"
              :title="`Live plan r${live.version}`"
              :name-of="nameOf"
              :focused="null"
              :selected="null"
              :availability="availability.state.value"
            />
            <DraftGantt
              :plan="proposal.plan"
              day=""
              :span="span"
              index="B2"
              :title="`Proposal · ${changeWords}`"
              :name-of="nameOf"
              :focused="null"
              :selected="null"
              :availability="availability.state.value"
            />
          </div>
          <ChangesPanel :diff="proposal.diff" :plan="proposal.plan" :name-of="nameOf" />
        </div>
        <PlanFooter
          :plan="footerPlan ?? proposal.plan"
          :is-admin="isAdmin"
          :busy="busy"
          :requests-left="stopped?.left ?? null"
          :sheet-label="applyLabel(proposal.plan)"
          @sheet="sheet?.open()"
          @execute="footerPlan && execute(footerPlan.id)"
          redraft-label="Propose again"
          @redraft="proposeAround"
        />
        <SubmitSheet
          v-if="primary?.kind === 'sheet'"
          ref="sheet"
          v-model:error="sheetError"
          :plan="proposal.plan"
          :name-of="nameOf"
          :commit-label="applyLabel(proposal.plan)"
          :confirm="isAdmin ? applyConfirm : primary.confirm"
          :busy="busy"
          @submit="onApply"
        />
      </template>
      <StationImpactPanel
        v-if="!proposal && station.stationId.value && station.availability.value.status === 'ready'"
        :mission-id="missionId"
        :station-id="station.stationId.value"
        :station-name="station.stationName.value"
        :availability="station.availability.value.value"
      />
      <UnconfirmedCallout v-if="!proposal" :plan="live" :name-of="nameOf" />
      <ApPanel v-if="!runView && !proposal" index="A2" title="Live plan">
        <ApCallout v-if="!repairableStates.includes(live.state)" tone="info">
          Live plan r{{ live.version }} is {{ live.state.replaceAll("_", " ") }}. Re-plan applies to
          plans with rejected or failed bookings.
        </ApCallout>
        <p v-else class="m-0 mb-3 text-base text-text-3">
          Live plan r{{ live.version }} is {{ live.state.replaceAll("_", " ") }}:
          {{ plural(live.counts.passes, "pass", "passes")
          }}<template v-if="coverage(live).spacecraft > 0"
            >, {{ spacecraftNotCovered(coverage(live).spacecraft) }}</template
          >. A re-plan keeps every committed pass and re-plans the rest. Nothing is booked until you
          apply it.
        </p>
        <ImpactPanel
          v-if="repairableStates.includes(live.state)"
          :live="live"
          :state="lost.state.value"
          :impact="lost.impact.value"
          :has-window="lost.hasWindow.value"
          @retry="lost.refetch"
        />
      </ApPanel>
      <ApCallout v-if="actionError" tone="caution">{{ replanErrorText(actionError) }}</ApCallout>
      <footer v-if="!proposal" class="flex flex-none justify-end border-t border-hairline pt-3">
        <ApButton
          v-if="!runId && repairableStates.includes(live.state)"
          variant="primary"
          size="commit"
          :disabled="busy"
          @click="proposeAround"
          >Propose a re-plan</ApButton
        >
        <ApButton
          v-else-if="runView?.kind === 'interrupted'"
          variant="primary"
          size="commit"
          :disabled="busy"
          @click="resume"
          >Continue re-planning</ApButton
        >
      </footer>
    </template>
  </ApRemote>
</template>
