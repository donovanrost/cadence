<script setup lang="ts">
import { ActivationsWaiting } from "@/features/activations/index.ts";
import { computed, onScopeDispose, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApPageHeader, ApRemote, formatShort, plural, refocusFirst } from "@/ui";
import ChangeSetBoard from "./ChangeSetBoard.vue";
import ChangesEmpty from "./ChangesEmpty.vue";
import ChangesOutcome from "./ChangesOutcome.vue";
import { blockingReason, previewChangeSet, type SubmitResult } from "./actions.ts";
import { useHeldChecks } from "./checks-view.ts";
import { conflictOps } from "./rebase.ts";
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
// ux B4: while the checks re-run for a moved version, K2 keeps the last ones (dimmed) and K3 waits.
const openSet = computed(() =>
  state.value.status === "ready" ? (state.value.value.change_set ?? null) : null,
);
const checks = useHeldChecks(
  () => preview.state.value,
  () => openSet.value?.staged_count ?? null,
  () => openSet.value?.id ?? null,
);

/**
 * #65 (ux): a blocking hold clears without the set changing (commands finish, a configuration is
 * activated), so while one blocks, re-run the checks on those updates and every 15 s as a backstop.
 */
const conflicts = computed(() =>
  conflictOps(preview.state.value.status === "ready" ? preview.state.value.value : null),
);
const blockingNow = computed(
  () =>
    preview.state.value.status === "ready" && blockingReason(preview.state.value.value) !== null,
);
useMissionInvalidation(
  missionId,
  ["commanding", "spacecraft", "configuration"],
  () => {
    if (blockingNow.value) preview.refetch();
  },
  { throttleMs: 2_000 },
);
const blockingPoll = setInterval(() => {
  if (blockingNow.value) preview.refetch();
}, 15_000);
onScopeDispose(() => clearInterval(blockingPoll));

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
  actAndRefetch();
}
// a11y A5: Apply, Request review, Approve & apply and Send back hide the board, and Discard all
// empties it, taking the focused control; once the page re-reads, land on the outcome, else
// Nothing staged. Rows that remain are ChangeList's to settle. Armed by an action only, so a first
// load never moves focus.
let acted = false;
function actAndRefetch() {
  acted = true;
  refetch();
}
const first = (selector: string) => document.querySelector<HTMLElement>(selector);
watch(
  [outcome, () => state.value],
  () => {
    if (!acted || state.value.status === "loading") return;
    acted = false;
    if (first("[data-change-row]")) return;
    refocusFirst(first("[data-changes-outcome]"), first("[data-changes-empty]"));
  },
  { flush: "post" },
);

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
/** The open set's next revision and size, while anything is staged. */
const staged = computed(() => {
  const s = state.value;
  const count = s.status === "ready" ? (s.value.change_set?.staged_count ?? 0) : 0;
  return s.status === "ready" && count > 0 ? { next: s.value.head.revision + 1, count } : null;
});
const subtitle = computed(() => (state.value.status === "ready" ? meta(state.value.value) : null));
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
      <template v-if="staged" #title
        >Apply <span class="font-mono normal-case">r{{ staged.next }}</span> ·
        {{ plural(staged.count, "change") }}</template
      >
      <template v-if="subtitle" #subtitle>
        <span class="font-mono text-sm text-text-3">{{ subtitle }}</span>
      </template>
    </ApPageHeader>
    <ActivationsWaiting :mission-id="missionId" />
    <ChangesEmpty v-if="notProvided" reason="unavailable" />
    <ChangesOutcome
      :outcome="outcome"
      :staged-notice="stagedNotice"
      :next="state.status === 'ready' ? state.value.head.revision + 1 : null"
    />
    <ApRemote
      v-if="!outcome"
      :state="state"
      loading-label="Loading staged changes…"
      @retry="refetch"
    >
      <template #default="{ value }">
        <ChangesEmpty
          v-if="!value.change_set || value.change_set.staged_count === 0"
          reason="nothing"
        />
        <ChangeSetBoard
          v-else
          :mission-id="missionId"
          :config="value"
          :change-set="value.change_set"
          :preview="preview.state.value"
          :held="checks.held.value"
          :checks-done="checks.done.value"
          :conflicts="conflicts"
          @reload="reloadAll"
          @result="onResult"
          @changed="actAndRefetch"
        />
      </template>
    </ApRemote>
  </div>
</template>
