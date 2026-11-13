<script setup lang="ts">
import { computed, ref } from "vue";
import { useRouter } from "vue-router";
import {
  failureOutcome,
  previewOps,
  refreshConfigState,
  stageChange,
  type Preview,
} from "@/features/changes/index.ts";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import type { SpacecraftDetail } from "./detail.ts";
import { archiveHolds, archiveOp } from "./edit.ts";

/** U40 Archive (L17 `delete`): the dry run's waiting/booked holds, then Stage archive. */
const props = defineProps<{ missionId: string; detail: SpacecraftDetail }>();
const router = useRouter();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const preview = ref<Preview | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
const holds = computed(() =>
  preview.value
    ? archiveHolds(preview.value, props.detail.spacecraft.id)
    : { waiting: null, booked: null },
);
const scId = computed(() => props.detail.spacecraft.scid);
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
  if (busy.value || holds.value.waiting) return;
  busy.value = true;
  try {
    const r = await stageChange(props.missionId, {
      summary: `Archive ${props.detail.spacecraft.name}`,
      source: { surface: "spacecraft" },
      ops: [archiveOp(props.detail)],
    });
    if (!r.ok) return void (failure.value = failureOutcome(r.error, "staged").sentence);
    refreshConfigState(props.missionId);
    sheet.value?.close();
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
    <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="holds.waiting !== null || busy"
        :disabled-reason="busy ? 'Staging…' : 'Release or cancel the waiting requests first.'"
        @click="stage"
        >Stage archive</ApButton
      >
    </template>
  </ApSheet>
</template>
