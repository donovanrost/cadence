<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { detailsOf, fieldErrors, isError, useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { ApButton, ApCallout, ApField, ApSelect, ApSheet } from "@/ui";
import type { DataSource } from "./api.ts";
import { blastRadiusReader, fetchBlastRadius, type BlastRadius } from "./bindings.ts";
import type { SwitchTarget } from "./BindingSwitchSheet.vue";
import * as words from "./platform.ts";
import { sourceFailure } from "./present.ts";
import { switchBinding } from "./writes.ts";

/** ux U53 / #90: switch a platform-wide binding (platform admin in admin mode); danger, audited. */
const props = defineProps<{ missionId: MissionId; sources: readonly DataSource[] }>();
const emit = defineEmits<{ done: [note: { tone: "nominal" | "crit"; text: string }] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const picked = ref<SwitchTarget | null>(null);
const opens = ref(0);
const key = ref<{ missionId: MissionId; bindingId: string; opens: number } | null>(null);
const radius = useRemoteQuery(key, fetchBlastRadius);
useMissionInvalidation(
  computed(() => props.missionId),
  ["data_sources", "contacts"],
  () => {
    if (key.value) radius.refetch();
  },
);
/** What the operator sees and confirms: the newest read, or the 409's fresh counts. */
const shown = ref<BlastRadius | null>(null);
const changed = ref<BlastRadius | null>(null);
const [reason, typed, target] = [ref(""), ref(""), ref("")];
const reasonError = ref<string | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
watch(
  () => (radius.state.value.status === "ready" ? radius.state.value.value : null),
  (next) => {
    if (!next) return;
    if (words.countsDiffer(shown.value, next)) typed.value = "";
    shown.value = next;
  },
);
const unavailable = computed(() => radius.state.value.status === "failed");
const name = computed(() => picked.value?.logical_source ?? "");
const nameOf = (id: string) => props.sources.find((s) => s.id === id)?.display_name ?? null;
const choices = computed(() =>
  words
    .platformTargets(props.sources, picked.value)
    .map((s) => ({ value: s.id, label: s.display_name })),
);
const lines = computed(() => {
  const r = shown.value;
  if (!r) return null;
  return {
    blast: words.blastLine(
      r,
      target.value ? nameOf(target.value) : null,
      nameOf(r.binding.from.id),
    ),
    live: words.livePassesLine(r, new Date()),
  };
});
const form = computed(() => ({
  reason: reason.value,
  typed: typed.value,
  name: name.value,
  target: target.value,
  current: picked.value?.data_source_id ?? "",
}));
const ready = computed(
  () => !busy.value && !unavailable.value && shown.value !== null && words.switchReady(form.value),
);
function open(b: SwitchTarget) {
  picked.value = b;
  [reason.value, typed.value, target.value] = ["", "", ""];
  [shown.value, changed.value, reasonError.value, failure.value] = [null, null, null, null];
  opens.value += 1;
  key.value = { missionId: props.missionId, bindingId: b.id, opens: opens.value };
  sheet.value?.open();
}
defineExpose({ open });
async function submit() {
  const b = picked.value;
  const r = shown.value;
  if (!b || !r || busy.value) return;
  if (reason.value.trim() === "") return void (reasonError.value = words.REASON_BLANK);
  busy.value = true;
  [reasonError.value, failure.value] = [null, null];
  try {
    const res = await switchBinding(props.missionId, b.id, {
      data_source_id: target.value,
      expected_data_source_id: b.data_source_id,
      reason: reason.value.trim(),
      expected_affected_missions: r.affected_missions,
      expected_live_passes_total: r.live_passes.total,
    });
    if (res.ok) {
      sheet.value?.close();
      const n = res.value.recorded?.affected_missions ?? r.affected_missions;
      emit("done", {
        tone: "nominal",
        text: words.outcomeLine(name.value, nameOf(target.value) ?? target.value, n),
      });
      return;
    }
    const fresh = isError(res.error, "blast_radius_changed")
      ? detailsOf(res.error, blastRadiusReader)
      : null;
    if (fresh) {
      [shown.value, changed.value, typed.value] = [fresh, fresh, ""];
      return;
    }
    reasonError.value = fieldErrors(res.error)["reason"] ?? null;
    if (!reasonError.value) failure.value = sourceFailure(res.error);
  } finally {
    busy.value = false;
  }
}
function close() {
  key.value = null;
}
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="shown ? words.sheetTitle(name, shown.affected_missions) : `Switch ${name}`"
    width="narrow"
    @closed="close"
  >
    <div class="flex flex-col gap-3">
      <ApCallout v-if="unavailable" tone="caution">{{ words.COUNTS_UNAVAILABLE }}</ApCallout>
      <p v-else-if="!lines" role="status" class="m-0 text-md text-text-3">Counting missions…</p>
      <template v-else>
        <ApCallout v-if="changed" tone="caution" role="alert">{{
          words.changedLine(changed)
        }}</ApCallout>
        <p class="m-0 text-md text-text-2" aria-live="polite">{{ lines.blast }}</p>
        <ApCallout v-if="lines.live" tone="crit">{{ lines.live }}</ApCallout>
        <ApSelect
          v-model="target"
          label="Read from"
          required
          :options="choices"
          placeholder="Choose another source"
        />
        <ApField
          v-model="reason"
          label="Reason"
          required
          :hint="words.REASON_HELP"
          :error="reasonError"
        />
        <ApField v-model="typed" :label="`Type ${name} to confirm`" mono required />
      </template>
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        v-if="!unavailable && shown"
        variant="danger"
        :disabled="!ready"
        :disabled-reason="busy ? 'Switching…' : words.blockedReason(form)"
        @click="submit"
        >{{ words.switchLabel(shown.affected_missions) }}</ApButton
      >
    </template>
  </ApSheet>
</template>
