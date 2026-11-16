<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import {
  FailureOutcomeCallout,
  failureOutcome,
  previewOps,
  refreshConfigState,
  stageChange,
  useConfigState,
  type FailureOutcome,
  type Preview,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import type { SpacecraftDetail } from "./detail.ts";
import { archiveHolds, archiveOp, archiveStaged } from "./edit.ts";

/** U40 Archive (L17 `delete`): the dry run's waiting/booked holds, then Stage archive. */
const props = defineProps<{ missionId: MissionId; detail: SpacecraftDetail }>();
const router = useRouter();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const preview = ref<Preview | null>(null);
const failure = ref<FailureOutcome | null>(null);
const busy = ref(false);
const holds = computed(() =>
  preview.value
    ? archiveHolds(preview.value, props.detail.spacecraft.id)
    : { waiting: null, booked: null },
);
const scId = computed(() => props.detail.spacecraft.scid);
const config = useConfigState(props.missionId);
/** Staged here, or already in the open change set: Stage archive doesn't stage it twice (qa). */
const staged = ref(false);
const already = computed(() => {
  const s = config.state.value;
  return (
    staged.value ||
    (s.status === "ready" && archiveStaged(s.value.change_set, props.detail.spacecraft.id))
  );
});
const blocked = computed((): string | null => {
  if (busy.value) return "Staging…";
  if (already.value) return "Already staged.";
  if (holds.value.waiting) return "Release or cancel the waiting requests first.";
  return null;
});
let controller: AbortController | null = null;

async function open() {
  preview.value = null;
  failure.value = null;
  sheet.value?.open();
  controller?.abort();
  controller = new AbortController();
  const r = await previewOps(
    { missionId: props.missionId, ops: [archiveOp(props.detail)] },
    controller.signal,
  );
  // U40: when the dry run can't tell, the sheet keeps its plain line and Changes' HOLD catches it.
  if (r.ok) preview.value = r.value;
}
function closed() {
  controller?.abort();
}
async function stage() {
  if (blocked.value !== null) return;
  busy.value = true;
  try {
    const r = await stageChange(props.missionId, {
      summary: `Archive ${props.detail.spacecraft.name}`,
      source: { surface: "spacecraft" },
      ops: [archiveOp(props.detail)],
    });
    if (!r.ok) return void (failure.value = failureOutcome(r.error, "staged"));
    staged.value = true;
    refreshConfigState(props.missionId);
    // If the navigation doesn't happen, the sheet stays open and says it's staged (qa 11-13).
    await router.push({ name: "setup.changes" });
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="`Archive ${detail.spacecraft.name}?`" @closed="closed">
    <p class="m-0 text-md text-text-2">
      It leaves the mission's lists, fleet and planning when the change is applied. Its history
      stays.
    </p>
    <ApCallout v-if="holds.waiting" tone="crit">
      {{ holds.waiting.sentence }}
      <template v-if="scId !== null" #action>
        <ApButton size="compact" :to="{ name: 'ops.spacecraft', params: { scId, tab: 'uplink' } }"
          >Open in Uplink</ApButton
        >
      </template>
    </ApCallout>
    <ApCallout v-if="holds.booked" tone="caution">
      {{ holds.booked.sentence }}
      <template v-if="scId !== null" #action>
        <ApButton size="compact" :to="{ name: 'ops.spacecraft', params: { scId, tab: 'passes' } }"
          >Open in Contacts</ApButton
        >
      </template>
    </ApCallout>
    <ApCallout v-if="already" tone="info">
      Archiving {{ detail.spacecraft.name }} is already staged. It happens when the change set is
      applied.
      <template #action>
        <ApButton size="compact" :to="{ name: 'setup.changes' }">Open Changes</ApButton>
      </template>
    </ApCallout>
    <FailureOutcomeCallout v-if="failure" :outcome="failure" />
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? ''"
        @click="stage"
        >Stage archive</ApButton
      >
    </template>
  </ApSheet>
</template>
