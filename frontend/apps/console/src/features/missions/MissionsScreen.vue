<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { fleetOpState, fleetStateWord } from "@/features/fleet/index.ts";
import { canAdministerOrganization, useConsoleScope, useSession } from "@/shell";
import {
  ApButton,
  ApCallout,
  type ApColumn,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApTable,
  ApTag,
  formatCount,
  plural,
  useActed,
} from "@/ui";
import { fetchMissionSummaries } from "./api.ts";

/**
 * Organization › Missions. Rows come from the session bootstrap (instant); fleet size and worst
 * state fill in from the org missions summary (pass-2 #11).
 */
const scope = useConsoleScope();
const organization = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const session = useSession();
/** L4: New mission is the console form (plans/mission-create.md). */
const canCreate = computed(() =>
  organization.value ? canAdministerOrganization(session, organization.value) : false,
);
const summaries = useRemoteQuery(() => organization.value?.id ?? null, fetchMissionSummaries);
/** B6 (#276): a failure after Retry is an alert; on load, polite. */
const summariesActed = useActed(() => summaries.state.value.status === "ready");
const summary = (id: string) =>
  summaries.state.value.status === "ready" ? summaries.state.value.value.get(id) : undefined;
const columns: readonly ApColumn[] = [
  { key: "name", label: "Mission" },
  { key: "fleet", label: "Fleet", align: "end", mono: true },
  { key: "state", label: "Worst state" },
  { key: "open", label: "Open", hiddenLabel: true },
];
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${organization?.name ?? ''} · organization`"
      :title="organization ? plural(organization.missions.length, 'mission') : 'Missions'"
      size="reading"
    >
      <ApButton v-if="canCreate" variant="primary" :to="{ name: 'org.missions.new' }"
        >New mission</ApButton
      >
    </ApPageHeader>
    <ApPanel index="M1" title="Missions" flush>
      <ApEmptyState
        v-if="!organization || organization.missions.length === 0"
        state="off"
        headline="No missions yet"
        sentence="A mission groups the spacecraft, profiles and catalog operated together."
      />
      <template v-else>
        <ApCallout
          v-if="summaries.state.value.status === 'failed'"
          tone="caution"
          :role="summariesActed.role.value"
        >
          Fleet size and state couldn't load.
          <template #action>
            <ApButton
              size="compact"
              @click="
                summariesActed.mark();
                summaries.refetch();
              "
              >Retry</ApButton
            >
          </template>
        </ApCallout>
        <ApTable
          :columns="columns"
          :rows="organization.missions"
          :row-key="(m) => m.id"
          caption="Missions"
        >
          <template #cell-name="{ row }">
            <RouterLink
              :to="{
                name: 'setup.readiness',
                params: { org: organization.slug, mission: row.slug },
              }"
              class="font-semibold text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
              >{{ row.name }}</RouterLink
            >
          </template>
          <template #cell-fleet="{ row }">
            <template v-if="summary(row.id)">{{
              formatCount(summary(row.id)?.spacecraft_count ?? 0)
            }}</template>
            <span v-else class="text-text-4" aria-label="Loading">—</span>
          </template>
          <template #cell-state="{ row }">
            <template v-if="summary(row.id)">
              <ApTag
                v-if="summary(row.id)?.worst_state"
                :state="fleetOpState(summary(row.id)?.worst_state ?? 'never_heard')"
                :label="fleetStateWord(summary(row.id)?.worst_state ?? 'never_heard')"
              />
              <span v-else class="text-text-3">No spacecraft</span>
            </template>
            <span v-else class="text-text-4" aria-label="Loading">—</span>
          </template>
          <template #cell-open="{ row }">
            <RouterLink
              :to="{ name: 'ops.now', params: { org: organization.slug, mission: row.slug } }"
              class="text-text-3 no-underline hover:text-readout max-md:hit-44"
              >Open in Ops →</RouterLink
            >
          </template>
        </ApTable>
      </template>
    </ApPanel>
  </div>
</template>
