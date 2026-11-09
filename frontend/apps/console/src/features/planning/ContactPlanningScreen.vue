<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import { ApCallout, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApTabLinks } from "@/ui";
import RequirementsTab from "./RequirementsTab.vue";
import { fetchPlanning, situation, type PlanningSummary } from "./api.ts";

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
const links = [
  { key: "requirements", label: "Requirements", to: { name: "setup.contact-planning" } },
  { key: "policy", label: "Policy", to: { name: "setup.contact-planning.policy" } },
];
const subline = (s: PlanningSummary) =>
  s.policy
    ? `Policy v${s.policy.version} · mode ${s.policy.mode === "advisory" ? "advisory" : "automatic submission"} · ${s.templates.length} templates cover ${s.coverage.covered} of ${s.coverage.spacecraft_total} spacecraft`
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
    <ApPanel v-if="notProvided" index="P1" title="Contact planning" flush>
      <ApEmptyState
        state="off"
        headline="Contact planning not available in the console yet"
        sentence="This server doesn't serve the planning policy and contact requirements to the console yet."
      />
    </ApPanel>
    <ApRemote v-else :state="state" loading-label="Loading contact planning…" @retry="refetch">
      <template #default="{ value }">
        <ApCallout v-if="value.policy === null" tone="off">
          The scheduler needs a policy and at least one contact rule before it can draft a day.
        </ApCallout>
        <ApTabLinks :links="links" :active="tab" label="Contact planning sections" />
        <RequirementsTab v-if="tab === 'requirements'" :summary="value" />
        <ApPanel v-else index="P4" title="Policy" flush>
          <ApEmptyState
            state="off"
            headline="Policy editing arrives with its endpoint"
            sentence="Mode, limits, reserves and diversity are edited here once the server serves the policy document and its fields."
          />
        </ApPanel>
      </template>
    </ApRemote>
  </div>
</template>
