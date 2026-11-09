<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApPageHeader, ApRemote, ApTag, formatAbsolute } from "@/ui";
import EntryList from "./EntryList.vue";
import RollbackPanel from "./RollbackPanel.vue";
import { useConfigState } from "./useConfigState.ts";
import { fetchRevision } from "./api.ts";

/**
 * Setup › Revisions › rN (Changes.md §4). Rollback (#49): on the live revision, roll back to the
 * one before it (undo); on an older one, roll back to it. Needs config.rollback.
 */
const route = useRoute();
const scope = useMissionScope();
const revision = computed(() => {
  const raw = route.params.revision;
  const n = typeof raw === "string" && /^\d+$/.test(raw) ? Number(raw) : null;
  return n !== null && n >= 1 ? n : null;
});
const key = computed(() =>
  revision.value === null ? null : { missionId: scope.value.mission.id, revision: revision.value },
);
const { state, refetch } = useRemoteQuery(key, fetchRevision);
const config = useConfigState(scope.value.mission.id);
const rollback = computed(() => {
  const c = config.state.value;
  const n = revision.value;
  if (c.status !== "ready" || n === null || !c.value.permissions.has("config.rollback"))
    return null;
  const head = c.value.head.revision;
  const to = n === head ? n - 1 : n < head ? n : null;
  return to !== null && to >= 1 ? { to, staged: c.value.change_set?.staged_count ?? 0 } : null;
});
const crumbs = computed(() => [
  { label: "Revisions", to: { name: "setup.revisions" } },
  { label: revision.value === null ? "Unknown" : `r${revision.value}` },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader :title="revision === null ? 'Revision' : `r${revision}`" size="reading">
      <template v-if="revision !== null" #title
        ><span class="font-mono normal-case">r{{ revision }}</span></template
      >
      <template v-if="state.status === 'ready' && state.value.live" #status
        ><ApTag state="live" label="Live"
      /></template>
      <template v-if="state.status === 'ready'" #subtitle>
        <span class="text-md text-text-3">
          Applied {{ formatAbsolute(new Date(state.value.applied_at)) }}
          <template v-if="state.value.applied_by"> by {{ state.value.applied_by.name }}</template>
          <template v-if="state.value.reason"> · “{{ state.value.reason }}”</template>
          <template v-for="a in state.value.approvals" :key="a.decided_at">
            · approved by {{ a.actor.name }}</template
          >
        </span>
      </template>
    </ApPageHeader>
    <ApRemote :state="state" loading-label="Loading revision…" @retry="refetch">
      <template #default="{ value }"><EntryList :entries="value.entries" /></template>
    </ApRemote>
    <RollbackPanel
      v-if="rollback"
      :key="rollback.to"
      :mission-id="scope.mission.id"
      :to="rollback.to"
      :staged-count="rollback.staged"
    />
  </div>
</template>
