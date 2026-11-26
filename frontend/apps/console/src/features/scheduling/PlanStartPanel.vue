<script setup lang="ts">
import { computed } from "vue";
import type { RouteLocationRaw } from "vue-router";
import type { ApiError } from "@/api";
import { ApButton, ApCallout } from "@/ui";
import type { PlanView } from "./plan-state.ts";
import PlanStatePanel from "./PlanStatePanel.vue";
import { limitRefusal, overLimit, type StartEstimate } from "./start-limit.ts";
import StartLimits from "./StartLimits.vue";

/**
 * K1 with no plan to show yet (moved out of PlanScreen for the 400-line rule, #654): the state
 * panel, U52's start limits, a refused act, and the one next step (set up, draft or continue).
 */
const props = defineProps<{
  view: Exclude<PlanView, { kind: "plan" }>;
  estimate: StartEstimate | null;
  actionError: ApiError | null;
  actionText: string | null;
  busy: boolean;
}>();
defineEmits<{ draft: []; resume: [] }>();
/** U52: over the limit, Start is disabled with the sentence StartLimits shows above it. */
const overReason = computed(() => overLimit(props.estimate));
const setupLink: RouteLocationRaw = { name: "setup.contact-planning" };
</script>

<template>
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
      @click="$emit('draft')"
      >Draft the day</ApButton
    >
    <ApButton
      v-else-if="view.kind === 'interrupted'"
      variant="primary"
      size="commit"
      :disabled="busy"
      disabled-reason="Working…"
      @click="$emit('resume')"
      >Continue drafting</ApButton
    >
  </footer>
</template>
