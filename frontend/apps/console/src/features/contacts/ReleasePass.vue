<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApCallout, ApSheet, outcomeRole } from "@/ui";
import { fetchQueuedGroups, type Pass, type QueuedGroups } from "./api.ts";
import { releasePass, whoMayRelease, type ReleaseOutcome } from "./release.ts";
import { stationLabel } from "./gantt.ts";

/**
 * D2 `Release pass` (contacts.md; ux copy): a danger confirm that names the pass, warns when it's
 * in progress or has command groups queued, then cancels at the provider. Members see why not.
 */
const props = defineProps<{ missionId: MissionId; pass: Pass; spacecraft: string; now: Date }>();
const emit = defineEmits<{ changed: [] }>();
const provider = computed(() => props.pass.source.provider_name ?? "the provider");
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const busy = ref(false);
const outcome = ref<ReleaseOutcome | null>(null);

const inProgress = computed(
  () => props.pass.state === "active" || props.pass.pass_phase === "pass",
);
/** Read when the sheet opens: the single pass read carries the queued groups (04755d23). */
const queued = ref<QueuedGroups | null>(null);
/** §4 short form: "03:00Z" today, "11-12 03:00Z" otherwise. */
const short = (iso: string) => {
  const today = iso.slice(0, 10) === props.now.toISOString().slice(0, 10);
  return `${today ? "" : `${iso.slice(5, 10)} `}${iso.slice(11, 16)}Z`;
};
const queuedLine = computed(() => {
  const q = queued.value;
  if (!q || q.count === 0) return null;
  const head = `${q.count} ${q.count === 1 ? "command group is" : "command groups are"} queued for this pass.`;
  const next = q.next_pass;
  if (!next) return `${head} No later pass is booked for ${q.count === 1 ? "it" : "them"} yet.`;
  const code = next.station.code ?? next.station.name;
  return `${head} ${q.count === 1 ? "It goes" : "They'll go"} on the next pass (${code ? `${code} ` : ""}${short(next.starts_at)}).`;
});

function open() {
  outcome.value = null;
  queued.value = null;
  fetchQueuedGroups(props.missionId, props.pass.id)
    .then((r) => {
      if (r.ok) queued.value = r.value.queued_command_groups ?? null;
    })
    .catch((e: unknown) => console.error("Queued groups read failed", e));
  sheet.value?.open();
}
async function release() {
  const rev = props.pass.provider_revision;
  if (rev === null || rev === undefined) return;
  busy.value = true;
  try {
    outcome.value = await releasePass(
      props.missionId,
      props.pass.id,
      rev,
      provider.value,
      props.pass.off_plan?.booked_by?.name ?? null,
    );
    sheet.value?.close();
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
      {{ whoMayRelease(pass.off_plan?.booked_by?.name ?? null) }}
    </p>
    <ApCallout v-if="outcome" :tone="outcome.tone" :role="outcomeRole(outcome.tone)">{{
      outcome.text
    }}</ApCallout>
    <ApSheet
      ref="sheet"
      :title="`Release ${spacecraft} · ${stationLabel(pass)} · ${short(pass.starts_at)}?`"
    >
      <p class="m-0 text-text-2">
        Cadence asks {{ provider }} to cancel this booking. If it accepts, the pass leaves the plan
        and Re-plan can fill the gap.
      </p>
      <ApCallout v-if="inProgress" tone="caution">
        This pass is in progress. Releasing it ends the contact now.
      </ApCallout>
      <ApCallout v-if="queuedLine" tone="caution">{{ queuedLine }}</ApCallout>
      <template #footer>
        <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
        <ApButton variant="danger" :disabled="busy" disabled-reason="Releasing…" @click="release"
          >Release pass</ApButton
        >
      </template>
    </ApSheet>
  </div>
</template>
