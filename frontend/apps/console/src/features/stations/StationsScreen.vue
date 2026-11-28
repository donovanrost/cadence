<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute } from "vue-router";
import { stationIdParam, useRemoteQuery, type StationId } from "@/api";
import { useMissionInvalidation } from "@/live";
import { paramText, useMissionScope } from "@/shell";
import {
  ApButton,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  ApTabLinks,
  plural,
  type ApTabLink,
} from "@/ui";
import ProvidersPanel from "./ProvidersPanel.vue";
import {
  FailureOutcomeCallout,
  KindEditor,
  StagedArchive,
  type RefusalOutcome,
  useCanStage,
} from "@/features/changes/index.ts";
import { stationName } from "./names.ts";
import StationsTable from "./StationsTable.vue";
import { fetchStations } from "./api.ts";
import { codeSuggestion, withCodeRule } from "./code-field.ts";
import { useConfirmCode } from "./useConfirmCode.ts";

/** Setup › Ground stations (rail 06). Edits stage into the change set (ground_station kind). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
/** ux U82: archived stations are hidden unless asked for, listed after the active ones. */
const showArchived = ref(false);
const { state, refetch } = useRemoteQuery(
  () => ({ missionId: missionId.value, archived: showArchived.value }),
  (key, signal) => fetchStations(key.missionId, signal, key.archived),
);
/** U82: an in-use refusal, shown in place of the confirm with what still uses it. */
const refused = ref<RefusalOutcome | null>(null);
/** The station being edited (null on Add): U82's header Archive… (an active one), U25's Code rule. */
const edited = computed(() =>
  state.value.status === "ready" && editing.value && editing.value !== "new"
    ? (state.value.value.find((s) => s.id === editing.value) ?? null)
    : null,
);
useMissionInvalidation(missionId, ["configuration"], refetch);
const route = useRoute();
const canStage = useCanStage(scope.value.mission.id);
/** `new` = add; an id = edit that station; none = list only. */
const editing = computed((): "new" | StationId | null =>
  paramText(route.params, "stationId") === "new"
    ? "new"
    : stationIdParam(paramText(route.params, "stationId")),
);
const tab = computed(() => (route.name === "setup.stations.providers" ? "providers" : "stations"));
const tabs: readonly ApTabLink[] = [
  { key: "stations", label: "Stations", to: { name: "setup.stations" } },
  { key: "providers", label: "Providers", to: { name: "setup.stations.providers" } },
];
const codes = useConfirmCode(() => missionId.value);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${scope.mission.name} · ground stations`"
      :title="
        state.status === 'ready'
          ? plural(state.value.filter((s) => s.lifecycle_state === 'active').length, 'station')
          : 'Ground stations'
      "
      size="reading"
    >
      <ApButton v-if="canStage" :to="{ name: 'setup.stations', params: { stationId: 'new' } }"
        >Add station</ApButton
      >
    </ApPageHeader>
    <ApTabLinks :links="tabs" :active="tab" label="Ground station sections" />
    <ProvidersPanel v-if="tab === 'providers'" :mission-id="missionId" />
    <FailureOutcomeCallout v-if="tab === 'stations' && refused" :outcome="refused" />
    <template v-if="tab === 'stations' && editing && canStage && state.status === 'ready'">
      <KindEditor
        :key="editing"
        :mission-id="missionId"
        kind="ground_station"
        :entity-id="editing === 'new' ? null : editing"
        :document="editing === 'new' ? {} : (state.value.find((s) => s.id === editing) ?? {})"
        :name="
          editing === 'new'
            ? 'station'
            : (state.value.find((s) => s.id === editing)?.display_name ?? 'station')
        "
        index="G2"
        surface="stations"
        :done="{ name: 'setup.stations' }"
        :prepare="withCodeRule(edited?.code ?? null)"
        :suggestion="codeSuggestion(edited?.suggested_code)"
      >
        <template v-if="edited?.lifecycle_state === 'active'" #actions>
          <StagedArchive
            :mission-id="missionId"
            kind="ground_station"
            :entity-id="edited.id"
            :name="stationName(edited)"
            surface="stations"
            variant="button"
            @refused="refused = $event"
          />
        </template>
      </KindEditor>
    </template>
    <ApPanel v-if="tab === 'stations'" index="G1" title="Stations" flush>
      <template #header>
        <label class="flex items-center gap-2 text-sm text-text-2">
          <input
            v-model="showArchived"
            type="checkbox"
            class="size-4 accent-[var(--color-readout)]"
          />
          Show archived
        </label>
      </template>
      <ApEmptyState
        v-if="notProvided"
        state="off"
        headline="Stations not available in the console yet"
        sentence="This server doesn't serve ground stations to the console yet."
      />
      <ApRemote v-else :state="state" loading-label="Loading stations…" @retry="refetch">
        <template #default="{ value }">
          <ApEmptyState
            v-if="value.length === 0"
            state="off"
            headline="No ground stations yet"
            sentence="Stations come from your ground-network providers or are added here."
          />
          <template v-else>
            <FailureOutcomeCallout v-if="codes.failure.value" :outcome="codes.failure.value" />
            <StationsTable
              :mission-id="missionId"
              :rows="value"
              :can-edit="canStage"
              :staged="codes.staged.value"
              :busy="codes.busy.value"
              @confirm="codes.confirm"
              @refused="refused = $event"
            />
          </template>
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
