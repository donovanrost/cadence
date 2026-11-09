<script setup lang="ts">
import { computed } from "vue";
import { describeApiError } from "@/api";
import { ApCallout, ApPanel, formatCount, formatRelative, useNow } from "@/ui";
import type { PlanView } from "./plan-state.ts";

/** K1 body for every state that isn't a plan (ScheduleFlow "K1 plan states"). */
const props = defineProps<{ view: Exclude<PlanView, { kind: "plan" }> }>();
const now = useNow();
const PHASES = ["materializing", "searching", "optimizing", "materializing_plan"] as const;
const MISSING: Readonly<Record<string, string>> = {
  fleet_planning_policy: "No planning policy",
  contact_requirements: "No active contact rule",
};
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
      <ul class="m-0 mt-3 list-none p-0 font-mono text-sm text-text-2 uppercase">
        <li v-for="item in view.missing" :key="item">
          {{ MISSING[item] ?? item.replaceAll("_", " ") }}
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
          · {{ formatCount(view.demand.without_rule) }} have no rule</template
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
          :class="phase === view.phase ? 'text-readout' : 'text-text-4'"
        >
          <span v-if="i > 0" aria-hidden="true">→</span
          >{{ phase === "materializing_plan" ? "plan" : phase }}
        </li>
      </ol>
      <p class="m-0 text-md text-text-3">
        Drafting with every provider's windows<span v-if="elapsed"> · {{ elapsed }}</span
        >. You can leave this page; the draft keeps running.
      </p>
    </div>
    <ApCallout v-else-if="view.kind === 'interrupted'" tone="stale">
      Drafting stopped when the server restarted<span v-if="view.phase">
        during {{ view.phase.replaceAll("_", " ") }}</span
      >. Nothing was submitted.
    </ApCallout>
    <ApCallout v-else-if="view.kind === 'draft_failed'" tone="caution">{{
      view.message
    }}</ApCallout>
    <ApCallout v-else-if="view.kind === 'failed'" tone="caution">{{
      describeApiError(view.error)
    }}</ApCallout>
    <p v-else role="status" class="m-0 font-mono text-sm text-text-4">Loading the plan…</p>
  </ApPanel>
</template>
