<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApEmptyState, ApPageHeader, ApPanel, ApRemote } from "@/ui";
import RevisionsTable from "./RevisionsTable.vue";
import { fetchRevisions } from "./api.ts";

/** Setup › Revisions (Changes.md §4): the mission's applied configuration revisions. */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchRevisions);
useMissionInvalidation(missionId, ["configuration"], refetch);

const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const live = computed(() =>
  state.value.status === "ready" ? (state.value.value.find((r) => r.live) ?? null) : null,
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${scope.mission.name} · configuration`"
      :title="live ? `Revisions · r${live.revision} live` : 'Revisions'"
      size="reading"
    >
      <template v-if="live" #title
        >Revisions · <span class="font-mono normal-case">r{{ live.revision }}</span> live</template
      >
      <template #subtitle>
        <span class="text-md text-text-3"
          >Every apply makes a revision. History is append-only; rolling back makes a new one.</span
        >
      </template>
    </ApPageHeader>
    <ApPanel index="V1" title="Revisions" flush>
      <ApEmptyState
        v-if="notProvided"
        state="off"
        headline="Revisions not available yet"
        sentence="This server doesn't serve mission revisions to the console yet."
      />
      <ApRemote v-else :state="state" loading-label="Loading revisions…" @retry="refetch">
        <template #default="{ value }">
          <ApEmptyState
            v-if="value.length === 0"
            headline="No revisions yet"
            sentence="The first apply creates the mission's baseline revision r1."
          />
          <RevisionsTable v-else :rows="value" />
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
