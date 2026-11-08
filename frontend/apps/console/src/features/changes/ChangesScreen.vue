<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApEmptyState, ApPageHeader, ApPanel, ApRemote, formatShort, plural } from "@/ui";
import ApplyAside from "./ApplyAside.vue";
import ChangeList from "./ChangeList.vue";
import { fetchConfigState } from "./api.ts";
import type { ConfigState } from "./shapes.ts";

/** Setup › Staged changes: review & apply the mission's one change set (Changes.md §3). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const { state, refetch } = useRemoteQuery(missionId, fetchConfigState);
useMissionInvalidation(missionId, ["configuration"], refetch);

const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const title = computed(() => {
  const s = state.value;
  if (s.status !== "ready") return "Staged changes";
  const set = s.value.change_set;
  if (!set || set.staged_count === 0) return "Nothing staged";
  return `Apply r${s.value.head.revision + 1} · ${plural(set.staged_count, "change")}`;
});
function meta(config: ConfigState): string | null {
  const set = config.change_set;
  if (!set || set.changes.length === 0) return null;
  const times = set.changes.map((c) => c.staged_at).sort();
  const first = times[0];
  const last = times.at(-1);
  if (!first || !last) return null;
  return `Base r${set.base_revision} · staged ${formatShort(new Date(first))}–${formatShort(new Date(last))}`;
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader :label="`${scope.mission.name} · staged changes`" :title="title" size="reading">
      <template v-if="state.status === 'ready' && meta(state.value)" #subtitle>
        <span class="font-mono text-sm text-text-3">{{ meta(state.value) }}</span>
      </template>
    </ApPageHeader>
    <ApPanel v-if="notProvided" index="K1" title="Changes" flush>
      <ApEmptyState
        state="off"
        headline="Change sets not available yet"
        sentence="This server doesn't serve mission change sets to the console yet."
      />
    </ApPanel>
    <ApRemote v-else :state="state" loading-label="Loading staged changes…" @retry="refetch">
      <template #default="{ value }">
        <ApPanel
          v-if="!value.change_set || value.change_set.staged_count === 0"
          index="K1"
          title="Changes"
          flush
        >
          <ApEmptyState
            headline="Nothing staged"
            sentence="Edits in Setup collect here before they reach the fleet."
          />
        </ApPanel>
        <div v-else class="flex flex-wrap items-start gap-4">
          <ChangeList :changes="value.change_set.changes" class="min-w-0 flex-[999_1_560px]" />
          <ApplyAside
            :config="value"
            :change-set="value.change_set"
            class="sticky top-0 min-w-0 flex-[1_1_340px]"
          />
        </div>
      </template>
    </ApRemote>
  </div>
</template>
