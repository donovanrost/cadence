<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApButton, ApEmptyState, ApPageHeader, ApPanel, ApRemote } from "@/ui";
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
/** Changes.md §4: pick two (checkbox column) → Compare rA ↔ rB; a third pick drops the oldest. */
const selected = ref<readonly number[]>([]);
function toggle(n: number) {
  selected.value = selected.value.includes(n)
    ? selected.value.filter((x) => x !== n)
    : [...selected.value, n].slice(-2);
}
const pair = computed(() => {
  const [a, b] = selected.value;
  return a === undefined || b === undefined ? null : { from: Math.min(a, b), to: Math.max(a, b) };
});
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
      <template #meta>
        <ApButton
          v-if="pair"
          size="compact"
          :to="{
            name: 'setup.revisions.compare',
            params: { from: String(pair.from), to: String(pair.to) },
          }"
          >Compare r{{ pair.from }} ↔ r{{ pair.to }}</ApButton
        >
        <span v-else class="text-text-3">Pick two to compare</span>
      </template>
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
          <RevisionsTable v-else :rows="value" :selected="selected" @toggle="toggle" />
        </template>
      </ApRemote>
    </ApPanel>
  </div>
</template>
