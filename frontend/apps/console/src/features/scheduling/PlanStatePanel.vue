<script setup lang="ts">
import { linkByName, type ParamlessRouteName } from "@/shell";
import { computed, onBeforeUnmount, watch } from "vue";
import { describeApiError, isKeyOf } from "@/api";
import { ApCallout, ApPanel, ApStatusMark, formatCount, formatRelative, useNow } from "@/ui";
import { runPhases, runPhaseText } from "./api.ts";
import { planActRole, settlePlanAct } from "./plan-acts.ts";
import type { PlanView } from "./plan-state.ts";

/**
 * K1 body for every state that isn't a plan (ScheduleFlow "K1 plan states"). Drafting is role=status,
 * so its ticking elapsed is aria-hidden (a11y B4); the current phase is aria-current and underlined (B2).
 */
const props = defineProps<{ view: Exclude<PlanView, { kind: "plan" }> }>();
/**
 * a11y B6 (#276, ux): a failure after the person's own act (Draft, Resume, Propose, a day change:
 * plan-acts.ts) is an alert; on first load or a background refetch it's read politely.
 */
const failureRole = planActRole;
const UNSETTLED: readonly string[] = ["loading", "drafting", "failed", "draft_failed"];
watch(
  () => props.view.kind,
  (kind) => {
    if (!UNSETTLED.includes(kind)) settlePlanAct();
  },
  { immediate: true },
);
onBeforeUnmount(settlePlanAct);
const now = useNow();
const PHASES = runPhases;
/** Setup gaps the console words (rule A); another gap reads as its key in words. */
const MISSING = {
  fleet_planning_policy: {
    text: "No planning policy",
    link: "Policy",
    route: "setup.contact-planning.policy",
  },
  contact_requirements: {
    text: "No active contact rule",
    link: "Requirements",
    route: "setup.contact-planning",
  },
} as const satisfies Readonly<
  Record<string, { text: string; link: string; route: ParamlessRouteName }>
>;
/** Each missing piece with its words and link, or null words for one the console doesn't word yet. */
const missing = computed(() =>
  props.view.kind === "not_set_up"
    ? props.view.missing.map((item) => ({
        item,
        gap: isKeyOf(MISSING, item) ? MISSING[item] : null,
      }))
    : [],
);
const elapsed = computed(() =>
  props.view.kind === "drafting" && props.view.startedAt
    ? formatRelative(new Date(props.view.startedAt), now.value).replace(/^T\+/, "")
    : null,
);
</script>

<template>
  <ApPanel index="A" title="Plan the day">
    <template v-if="view.kind === 'not_set_up'">
      <ApCallout tone="off"
        >Cadence needs a planning policy and at least one contact rule before it can draft a
        day.</ApCallout
      >
      <ul class="m-0 mt-3 list-none border border-hairline p-0">
        <li
          v-for="{ item, gap } in missing"
          :key="item"
          class="flex items-center gap-3 border-t border-hairline px-4 py-2.5 first:border-t-0"
        >
          <ApStatusMark state="off" />
          <span class="flex-1 text-base text-readout">{{
            gap?.text ?? item.replaceAll("_", " ")
          }}</span>
          <RouterLink
            v-if="gap"
            :to="linkByName(gap.route)"
            class="max-md:hit-44 font-mono text-sm text-readout"
            >{{ gap.link }} →</RouterLink
          >
        </li>
      </ul>
    </template>
    <div v-else-if="view.kind === 'no_draft'" class="flex flex-col gap-2">
      <p class="m-0 text-base text-text-3">
        There's no plan for this day yet. Cadence drafts the day across every provider's windows,
        then you work the exceptions.
      </p>
      <p v-if="view.demand" class="m-0 font-mono text-sm text-text-2 uppercase">
        {{ formatCount(view.demand.spacecraft_with_rules) }} spacecraft have rules ·
        {{ formatCount(view.demand.contacts_needed) }} contacts needed
        <template v-if="view.demand.without_rule > 0">
          ·
          <RouterLink :to="{ name: 'setup.contact-planning' }" class="max-md:hit-44 text-readout"
            >{{ formatCount(view.demand.without_rule) }} have no rule →</RouterLink
          ></template
        >
      </p>
      <p v-if="view.last" class="m-0 font-mono text-sm text-text-3 uppercase">
        Last plan for this day: r{{ view.last.version }},
        {{ view.last.state.replaceAll("_", " ") }} · {{ view.last.counts.passes }} passes
      </p>
    </div>
    <div v-else-if="view.kind === 'drafting'" role="status" class="flex flex-col gap-2">
      <ol
        class="m-0 flex list-none flex-wrap gap-2 p-0 font-mono text-sm uppercase"
        aria-label="Drafting phases"
      >
        <li
          v-for="(phase, i) in PHASES"
          :key="phase"
          class="flex items-center gap-2"
          :class="
            phase === view.phase ? 'text-readout underline underline-offset-4' : 'text-text-4'
          "
          :aria-current="phase === view.phase ? 'step' : undefined"
        >
          <span v-if="i > 0" aria-hidden="true">→</span
          >{{ phase === "materializing_plan" ? "plan" : phase }}
        </li>
      </ol>
      <p class="m-0 text-md text-text-3">
        Drafting with every provider's windows<span v-if="elapsed" aria-hidden="true">
          · {{ elapsed }}</span
        >. You can leave this page; the draft keeps running.
      </p>
    </div>
    <ApCallout v-else-if="view.kind === 'interrupted'" tone="stale">
      <!-- U20: no cause unless the server reports one; the console can't know it. -->
      <!-- ux: state the fact we have. stopped_at on an interrupted run is its last recorded
           progress (scheduling.md), not the moment it stopped. -->
      <template v-if="view.stoppedAt"
        >Drafting stopped. Last progress {{ view.stoppedAt.slice(11, 16) }}Z<span v-if="view.phase">
          during {{ runPhaseText(view.phase) }}</span
        >. Nothing was submitted.</template
      >
      <template v-else
        >Drafting stopped<span v-if="view.phase"> during {{ runPhaseText(view.phase) }}</span
        >. Nothing was submitted.</template
      >
    </ApCallout>
    <ApCallout v-else-if="view.kind === 'draft_failed'" tone="caution" :role="failureRole">{{
      view.message
    }}</ApCallout>
    <ApCallout v-else-if="view.kind === 'failed'" tone="caution" :role="failureRole">{{
      describeApiError(view.error)
    }}</ApCallout>
    <p v-else role="status" class="m-0 font-mono text-sm text-text-4">Loading the plan…</p>
  </ApPanel>
</template>
