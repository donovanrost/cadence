<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import {
  ApButton,
  ApCallout,
  ApEmptyState,
  ApPageHeader,
  ApPanel,
  ApRemote,
  formatShort,
  plural,
} from "@/ui";
import ApplyAside from "./ApplyAside.vue";
import ChangeList from "./ChangeList.vue";
import ChecksPanel from "./ChecksPanel.vue";
import ReviewPanel from "./ReviewPanel.vue";
import { previewChangeSet, type SubmitResult } from "./actions.ts";
import { refreshConfigState } from "./useConfigState.ts";
import { fetchConfigState } from "./api.ts";
import type { ConfigState } from "./shapes.ts";

/** Setup › Staged changes: review & apply the mission's one change set (Changes.md §3). */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const query = useRemoteQuery(missionId, fetchConfigState);
const state = query.state;
/** Refetch this page and the shared chrome (top bar status, staged bar). */
function refetch() {
  query.refetch();
  refreshConfigState(missionId.value);
}
useMissionInvalidation(missionId, ["configuration"], refetch);

// The dry run of the open set, re-run whenever the set's version moves.
const previewKey = computed(() => {
  const s = state.value;
  const set = s.status === "ready" ? s.value.change_set : null;
  return set && set.staged_count > 0
    ? { missionId: missionId.value, changeSetId: set.id, version: set.version }
    : null;
});
const preview = useRemoteQuery(previewKey, previewChangeSet);

function reloadAll() {
  refetch();
  preview.refetch();
}

// One-time note after staging from another surface (ux: say what staging did and when it lands).
const route = useRoute();
const router = useRouter();
const stagedNotice = ref<number | null>(
  typeof route.query.stagedSpacecraft === "string" && /^\d+$/.test(route.query.stagedSpacecraft)
    ? Number(route.query.stagedSpacecraft)
    : null,
);
if (stagedNotice.value !== null)
  void router.replace({ name: "setup.changes" }).catch(() => undefined);

// Kept here so the outcome survives the set closing (the aside unmounts on apply).
const outcome = ref<SubmitResult | null>(null);
function onResult(result: SubmitResult) {
  outcome.value = result;
  refetch();
}
const reviewing = (config: ConfigState) =>
  config.change_set?.state === "in_review" && config.permissions.has("config.review");

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
      <template
        v-if="state.status === 'ready' && (state.value.change_set?.staged_count ?? 0) > 0"
        #title
        >Apply <span class="font-mono normal-case">r{{ state.value.head.revision + 1 }}</span> ·
        {{ plural(state.value.change_set?.staged_count ?? 0, "change") }}</template
      >
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
    <ApCallout v-if="stagedNotice !== null && state.status === 'ready' && !outcome" tone="nominal">
      {{ plural(stagedNotice, "spacecraft", "spacecraft") }} staged. They're created when this
      change set is applied as <span class="font-mono">r{{ state.value.head.revision + 1 }}</span
      >.
    </ApCallout>
    <ApCallout v-if="outcome?.state === 'applied'" tone="nominal">
      <span class="font-mono normal-case">r{{ outcome.revision }}</span> applied ·
      {{ plural(outcome.staged_count, "change")
      }}<template v-if="outcome.runtime === 'degraded'">
        · the runtime hasn't converged on
        {{ outcome.degraded_partitions.length }} partitions</template
      >
      <template #action
        ><ApButton size="compact" :to="{ name: 'setup.revisions' }"
          >View revisions</ApButton
        ></template
      >
    </ApCallout>
    <ApCallout v-else-if="outcome?.state === 'in_review'" tone="info">
      Sent for review. An org member who didn't stage any of these changes approves or sends it
      back.
    </ApCallout>
    <ApCallout v-else-if="outcome?.state === 'open'" tone="info">
      Sent back to the authors with your comment.
    </ApCallout>
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
          <div class="flex min-w-0 flex-[999_1_560px] flex-col gap-4">
            <ChangeList
              :mission-id="missionId"
              :config="value"
              :change-set="value.change_set"
              @changed="refetch"
            />
            <ChecksPanel :preview="preview.state.value" @retry="reloadAll" />
          </div>
          <ReviewPanel
            v-if="reviewing(value)"
            :mission-id="missionId"
            :config="value"
            :change-set="value.change_set"
            class="sticky top-0 min-w-0 flex-[1_1_340px]"
            @result="onResult"
            @changed="refetch"
          />
          <ApplyAside
            v-else
            :mission-id="missionId"
            :config="value"
            :change-set="value.change_set"
            :preview="preview.state.value"
            class="sticky top-0 min-w-0 flex-[1_1_340px]"
            @result="onResult"
            @changed="refetch"
          />
        </div>
      </template>
    </ApRemote>
  </div>
</template>
