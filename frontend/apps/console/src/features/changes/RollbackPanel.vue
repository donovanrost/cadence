<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { ApButton, ApCallout, ApPanel, ApRemote, plural } from "@/ui";
import ChecksPanel from "./ChecksPanel.vue";
import { itemLine } from "./actions.ts";
import RollbackOps from "./RollbackOps.vue";
import { fetchRollback, rollbackErrorText, stageRollback } from "./rollback.ts";
import { refreshConfigState } from "./useConfigState.ts";

/**
 * Roll back to rN (DECISIONS #49): preview first (writes nothing), then stage it as a new change
 * set that goes through review like any other. Danger tone only in the confirm (Changes.md §4).
 */
const props = defineProps<{ missionId: string; to: number; stagedCount: number }>();
const router = useRouter();
const open = ref(false);
const busy = ref(false);
const failure = ref<string | null>(null);
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
/** The first NO-GO item in words, e.g. "Spacecraft can't be removed yet" (domain archive pending). */
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

async function stage() {
  busy.value = true;
  failure.value = null;
  try {
    const r = await stageRollback(props.missionId, props.to);
    if (!r.ok) return void (failure.value = rollbackErrorText(r.error, props.to));
    refreshConfigState(props.missionId);
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="V2" :title="`Roll back to r${to}`">
    <div class="flex flex-col gap-3">
      <p class="m-0 text-md text-text-3">
        A rollback is a new revision that reverses later ones. History isn't rewritten.
      </p>
      <div v-if="!open">
        <ApButton :disabled="blocked !== null" :disabled-reason="blocked ?? ''" @click="open = true"
          >Roll back to r{{ to }}</ApButton
        >
      </div>
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
          <p class="m-0 font-semibold text-readout">{{ value.summary }}</p>
          <RollbackOps :ops="value.ops" />
          <ApCallout v-if="value.outside.length > 0" tone="caution">
            {{ plural(value.outside.length, "item") }} changed outside change sets since r{{ to }}.
            The rollback overwrites them; you'll acknowledge that when you submit.
          </ApCallout>
          <ApCallout v-if="value.preview === null" tone="info"
            >Nothing differs from the live revision.</ApCallout
          >
          <ApCallout v-if="noGo" tone="crit"
            >This rollback can't be staged: {{ noGoReason }}</ApCallout
          >
          <ChecksPanel v-if="checks" :preview="checks" @retry="preview.refetch" />
        </template>
      </ApRemote>
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
      <div
        v-if="open && preview.state.value.status === 'ready'"
        class="flex flex-wrap items-center gap-2"
      >
        <ApButton
          variant="danger"
          :disabled="busy || noGo || preview.state.value.value.preview === null"
          :disabled-reason="
            busy ? 'Staging…' : noGo ? 'The checks say NO-GO' : 'Nothing to roll back'
          "
          @click="stage"
          >Stage rollback to r{{ to }}</ApButton
        >
        <ApButton variant="ghost" @click="open = false">Cancel</ApButton>
      </div>
    </div>
  </ApPanel>
</template>
