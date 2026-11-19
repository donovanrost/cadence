<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { ApButton, ApCallout, ApPanel, ApRemote, plural } from "@/ui";
import { failureOutcome, type FailureOutcome } from "./actions.ts";
import { itemLine } from "./itemLines.ts";
import RollbackActions from "./RollbackActions.vue";
import RollbackPreviewBody from "./RollbackPreviewBody.vue";
import { fetchRollback, rollbackErrorText, stageRollback } from "./rollback.ts";
import { refreshConfigState } from "./useConfigState.ts";

/**
 * Roll back to rN (DECISIONS #49): preview first (writes nothing), then stage it as a new change
 * set that goes through review like any other. Danger tone only in the confirm (Changes.md §4).
 */
const props = defineProps<{ missionId: MissionId; to: number; stagedCount: number }>();
const router = useRouter();
const open = ref(false);
const busy = ref(false);
const failure = ref<string | null>(null);
/** #413: a refusal's way out (U79 conversion_in_progress: Open change set), beside its words. */
const failureLink = ref<FailureOutcome["link"] | null>(null);
const preview = useRemoteQuery(
  () => (open.value ? { missionId: props.missionId, to: props.to } : null),
  fetchRollback,
);
const blocked = computed(() =>
  props.stagedCount > 0
    ? `Apply or discard the ${plural(props.stagedCount, "staged change")} first`
    : null,
);
const noGo = computed(
  () =>
    preview.state.value.status === "ready" &&
    preview.state.value.value.preview?.verdict === "no_go",
);
/** The first NO-GO item in words (any kind; spacecraft creation is now an archive + HOLD, not NO-GO). */
const noGoReason = computed(() => {
  const p = preview.state.value.status === "ready" ? preview.state.value.value.preview : null;
  const item = p?.checks.find((c) => c.verdict === "no_go")?.items[0];
  return item ? itemLine(item) : "a check says NO-GO.";
});
/** The preview's checks as a RemoteState for ChecksPanel (null when nothing differs). */
const checks = computed(() => {
  const st = preview.state.value;
  return st.status === "ready" && st.value.preview
    ? { status: "ready" as const, value: st.value.preview, receivedAt: st.receivedAt }
    : null;
});

/** Why Stage rollback is off, or null when it can stage. */
const stageBlocked = computed(() =>
  busy.value
    ? "Staging…"
    : noGo.value
      ? "The checks say NO-GO"
      : checks.value === null
        ? "Nothing to roll back"
        : null,
);
// U17 (header): the revision id keeps its case (mono, normal-case); the rest is a panel title.

async function stage() {
  busy.value = true;
  failure.value = null;
  failureLink.value = null;
  try {
    const r = await stageRollback(props.missionId, props.to);
    if (!r.ok) {
      failure.value = rollbackErrorText(r.error, props.to);
      failureLink.value = failureOutcome(r.error, "staged").link ?? null;
      return;
    }
    refreshConfigState(props.missionId);
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="V3">
    <template #header>
      <h2 class="m-0 font-display text-base font-semibold tracking-title text-text-2 uppercase">
        Roll back to <span class="font-mono normal-case">r{{ to }}</span>
      </h2>
    </template>
    <div class="flex flex-col gap-3">
      <p class="m-0 text-md text-text-3">
        A rollback is a new revision that reverses later ones. History isn't rewritten.
      </p>
      <ApButton
        v-if="!open"
        class="self-start"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? ''"
        @click="open = true"
        >Roll back to <span class="font-mono normal-case">r{{ to }}</span></ApButton
      >
      <ApCallout v-else-if="preview.state.value.status === 'failed'" tone="caution">
        {{ rollbackErrorText(preview.state.value.error, to) }}
      </ApCallout>
      <ApRemote
        v-else
        :state="preview.state.value"
        loading-label="Checking the rollback…"
        @retry="preview.refetch"
      >
        <template #default="{ value }">
          <RollbackPreviewBody
            :value="value"
            :to="to"
            :no-go-reason="noGo ? noGoReason : null"
            :checks="checks"
            @retry="preview.refetch"
          />
        </template>
      </ApRemote>
      <ApCallout v-if="failure" tone="crit"
        >{{ failure }}
        <template v-if="failureLink" #action>
          <ApButton size="compact" :to="failureLink.to">{{ failureLink.label }}</ApButton>
        </template>
      </ApCallout>
      <RollbackActions
        v-if="open && preview.state.value.status === 'ready'"
        :to="to"
        :blocked="stageBlocked"
        @stage="stage"
        @cancel="open = false"
      />
    </div>
  </ApPanel>
</template>
