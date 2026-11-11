<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import type { Pass } from "./api.ts";
import { releasePass, type ReleaseOutcome } from "./release.ts";
import { stationLabel } from "./gantt.ts";

/**
 * D2 `Release pass` (contacts.md; ux copy): a danger confirm that names the pass, warns when it's
 * in progress or has command groups queued, then cancels at the provider. Members see why not.
 */
const props = defineProps<{ missionId: string; pass: Pass; spacecraft: string; now: Date }>();
const emit = defineEmits<{ changed: [] }>();
const provider = computed(() => props.pass.source.provider_name ?? "the provider");
const dialog = ref<HTMLDialogElement | null>(null);
const titleId = `ap-release-${Math.random().toString(36).slice(2, 9)}`;
const busy = ref(false);
const outcome = ref<ReleaseOutcome | null>(null);

/** §4 short form: "03:00Z" today, "11-12 03:00Z" otherwise. */
const when = computed(() => {
  const at = props.pass.starts_at;
  const today = at.slice(0, 10) === props.now.toISOString().slice(0, 10);
  return `${today ? "" : `${at.slice(5, 10)} `}${at.slice(11, 16)}Z`;
});
const inProgress = computed(
  () => props.pass.state === "active" || props.pass.pass_phase === "pass",
);
const queued = computed(() => props.pass.uplink_readiness?.command_groups_queued ?? 0);

function open() {
  outcome.value = null;
  dialog.value?.showModal();
  void nextTick(() => dialog.value?.querySelector<HTMLElement>("footer button")?.focus());
}
async function release() {
  const rev = props.pass.provider_revision;
  if (rev === null || rev === undefined) return;
  busy.value = true;
  try {
    outcome.value = await releasePass(props.missionId, props.pass.id, rev, provider.value);
    dialog.value?.close();
    emit("changed");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="flex flex-col gap-2">
    <ApButton
      v-if="pass.releasable && pass.provider_revision != null"
      size="compact"
      variant="secondary"
      @click="open"
      >Release pass</ApButton
    >
    <p
      v-else-if="
        pass.releasable === false && ['pending', 'confirmed', 'active'].includes(pass.state)
      "
      class="m-0 text-sm text-text-2"
    >
      Org admins can release a booking.
    </p>
    <ApCallout v-if="outcome" :tone="outcome.tone">{{ outcome.text }}</ApCallout>
    <dialog
      ref="dialog"
      :aria-labelledby="titleId"
      aria-modal="true"
      class="m-auto w-[min(560px,calc(100vw-32px))] border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
    >
      <div class="flex flex-col gap-3 p-5">
        <h2 :id="titleId" class="m-0 font-display text-xl font-semibold tracking-tag uppercase">
          Release {{ spacecraft }} · {{ stationLabel(pass) }} · {{ when }}?
        </h2>
        <p class="m-0 text-text-2">
          Cadence asks {{ provider }} to cancel this booking. If it accepts, the pass leaves the
          plan and Re-plan can fill the gap.
        </p>
        <ApCallout v-if="inProgress" tone="caution">
          This pass is in progress. Releasing it ends the contact now.
        </ApCallout>
        <ApCallout v-if="queued > 0" tone="caution">
          {{ queued }} {{ queued === 1 ? "command group is" : "command groups are" }} queued for
          this pass. They'll go on the next pass.
        </ApCallout>
      </div>
      <footer class="flex items-center justify-end gap-2 border-t border-hairline px-5 py-3">
        <ApButton variant="ghost" @click="dialog?.close()">Cancel</ApButton>
        <ApButton variant="danger" :disabled="busy" @click="release">Release pass</ApButton>
      </footer>
    </dialog>
  </div>
</template>
