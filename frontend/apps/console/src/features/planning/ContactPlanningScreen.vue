<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import {
  ApCallout,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTabLinks,
  type ApTabLink,
} from "@/ui";
import GrantsPanel from "./GrantsPanel.vue";
import PolicyTab from "./PolicyTab.vue";
import RequirementsTab from "./RequirementsTab.vue";
import { vocabularyText } from "@/api";
import { automationWords, fetchPlanning, situation, type PlanningSummary } from "./api.ts";

/** Setup › Contact planning (DECISIONS #27). Spec: docs/apogee/ux/screens/ContactPlanning.md. */
const route = useRoute();
const scope = useMissionScope();
const { state, refetch } = useRemoteQuery(() => scope.value.mission.id, fetchPlanning);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const tab = computed(() =>
  route.name === "setup.contact-planning.policy" ? "policy" : "requirements",
);
const links: readonly ApTabLink[] = [
  { key: "requirements", label: "Requirements", to: { name: "setup.contact-planning" } },
  { key: "policy", label: "Policy", to: { name: "setup.contact-planning.policy" } },
];
const subline = (s: PlanningSummary) =>
  s.policy
    ? `Policy v${s.policy.version} · ${vocabularyText(s.policy.mode, automationWords)} · ${s.templates.length} templates cover ${s.coverage.covered} of ${s.coverage.spacecraft_total} spacecraft`
    : null;
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${scope.mission.name} · contact planning`"
      :title="state.status === 'ready' ? situation(state.value) : 'Contact planning'"
      size="reading"
    >
      <template v-if="state.status === 'ready' && subline(state.value)" #subtitle
        ><span class="text-md text-text-3">{{ subline(state.value) }}</span></template
      >
    </ApPageHeader>
    <ApTabLinks :links="links" :active="tab" label="Contact planning sections" />
    <!-- Tabs load independently: the policy (CP2) works while the summary (CP1) isn't served yet. -->
    <template v-if="tab === 'policy'">
      <PolicyTab :mission-id="scope.mission.id" />
      <GrantsPanel :mission-id="scope.mission.id" />
    </template>
    <ApPanel v-else-if="notProvided" index="P1" title="Requirements" flush>
      <ApEmptyState
        state="off"
        headline="Contact requirements aren't available in the console yet"
        sentence="The requirement templates and coverage arrive with their endpoint. The policy can be set up already."
      />
    </ApPanel>
    <ApRemote v-else :state="state" loading-label="Loading contact planning…" @retry="refetch">
      <template #default="{ value }">
        <ApCallout v-if="value.policy === null" tone="off">
          The scheduler needs a policy and at least one contact rule before it can draft a day.
        </ApCallout>
        <RequirementsTab :summary="value" :mission-id="scope.mission.id" />
      </template>
    </ApRemote>
  </div>
</template>
