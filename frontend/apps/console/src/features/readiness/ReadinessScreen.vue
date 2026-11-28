<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { useCanStage } from "@/features/changes/index.ts";
import { ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApTag } from "@/ui";
import AreaTile from "./AreaTile.vue";
import FindingsPanel from "./FindingsPanel.vue";
import RecentChangesPanel from "./RecentChangesPanel.vue";
import { areaKeys, fetchReadiness } from "./api.ts";
import { areaName, verdictSubline, verdictTitle } from "./present.ts";

/** S1 · Is the mission ready? Spec: docs/apogee/ux/screens/Setup.md. */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchReadiness);
useMissionInvalidation(
  missionId,
  ["spacecraft", "catalog", "data_sources", "settings", "limits"],
  refetch,
);

// #1160: each header action reads the server's own check: adding spacecraft stages a change
// (config.stage), importing is the upload's (catalog.import). Both are any mission operator.
const canStage = useCanStage(scope.value.mission.id);
const canImport = computed(() => state.value.status === "ready" && state.value.value.canImport);

const label = computed(() => `${scope.value.mission.name} · mission readiness`);
const title = computed(() => {
  const s = state.value;
  if (s.status === "ready") return verdictTitle(s.value);
  return s.status === "loading" ? "Loading…" : "Readiness not available";
});
// The mission itself resolved in the shell, so a 404 here means this server has no readiness checks.
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader :label="label" :title="title" size="reading">
      <template v-if="state.status === 'ready'" #status>
        <ApTag
          :state="state.value.verdict.blocker === 0 ? 'nominal' : 'crit'"
          :label="`${state.value.verdict.blocker} ${state.value.verdict.blocker === 1 ? 'blocker' : 'blockers'}`"
        />
      </template>
      <template v-if="state.status === 'ready' && verdictSubline(state.value)" #subtitle>
        <span class="text-md text-text-3">{{ verdictSubline(state.value) }}</span>
      </template>
      <div v-if="canStage || canImport" class="flex flex-wrap gap-2">
        <ApButton v-if="canStage" :to="{ name: 'setup.spacecraft.new' }">Add spacecraft</ApButton>
        <ApButton v-if="canImport" :to="{ name: 'setup.catalog.import' }">Import catalog</ApButton>
      </div>
    </ApPageHeader>

    <section
      v-if="state.status === 'loading'"
      aria-label="Readiness areas"
      class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 min-[1800px]:grid-cols-6 gap-px border border-hairline bg-hairline"
    >
      <div v-for="key in areaKeys" :key="key" class="flex flex-col gap-2 bg-panel px-4 py-3.5">
        <span class="font-display text-[17px] font-semibold tracking-title uppercase">{{
          areaName(key)
        }}</span>
        <span aria-hidden="true" class="text-[28px] leading-none text-text-4">—</span>
      </div>
    </section>

    <ApPanel v-if="notProvided" index="R1" title="Findings" flush>
      <ApEmptyState
        state="off"
        headline="Readiness checks not available yet"
        sentence="This server doesn't report mission readiness yet. The spacecraft, catalog and routing pages show their own state in the meantime."
      >
        <ApButton size="compact" @click="refetch">Check again</ApButton>
      </ApEmptyState>
    </ApPanel>
    <ApRemote v-else :state="state" loading-label="Checking readiness…" @retry="refetch">
      <template #default="{ value }">
        <section
          aria-label="Readiness areas"
          class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 min-[1800px]:grid-cols-6 gap-px border border-hairline bg-hairline"
        >
          <AreaTile v-for="area in value.areas" :key="area.key" :area="area" />
        </section>
        <div class="flex flex-wrap items-start gap-4">
          <FindingsPanel :readiness="value" class="min-w-0 flex-[999_1_560px]" />
          <RecentChangesPanel :changes="value.recentChanges" class="min-w-0 flex-[1_1_340px]" />
        </div>
      </template>
    </ApRemote>
  </div>
</template>
