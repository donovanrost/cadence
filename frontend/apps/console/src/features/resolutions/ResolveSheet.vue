<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApCallout, ApSheet } from "@/ui";
import ResolveFields from "./ResolveFields.vue";
import { failureText, outcomeText, resolveUnconfirmed, type ResolveAction } from "./api.ts";
import type { ResolvablePass } from "./types.ts";

/**
 * ux U32 sheets: Mark booked / Mark not booked for one unconfirmed pass. Cadence re-asks the
 * provider first; the outcome replaces the form, and `resolved` tells the screen to refetch.
 */
const props = defineProps<{ missionId: MissionId; planId: string; pass: ResolvablePass }>();
const emit = defineEmits<{ resolved: [] }>();

const action = ref<ResolveAction>("booked");
const note = ref("");
const reference = ref("");
const errors = ref<Record<string, string>>({});
const failure = ref<string | null>(null);
const outcome = ref<string | null>(null);
const busy = ref(false);
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);

const provider = computed(() => props.pass.provider?.name ?? "the provider");
const booked = computed(() => action.value === "booked");
const title = computed(
  () => `Mark ${props.pass.text} as ${booked.value ? "booked" : "not booked"}`,
);
/** ux: one request does both for not-booked, and the client can't tell which step it's on. */
const busyText = computed(() =>
  booked.value
    ? `Asking ${provider.value} first…`
    : `Asking ${provider.value}, then sending the cancel…`,
);
const primary = computed(() =>
  booked.value ? "Mark booked" : `Cancel at ${provider.value} and mark not booked`,
);

function open(next: ResolveAction) {
  action.value = next;
  note.value = "";
  reference.value = "";
  errors.value = {};
  failure.value = null;
  outcome.value = null;
  sheet.value?.open();
}
defineExpose({ open });

async function submit() {
  if (busy.value) return;
  const local: Record<string, string> = {};
  if (booked.value && !reference.value.trim())
    local["provider_reference"] = `Enter the ${provider.value} booking reference.`;
  if (!note.value.trim()) local["note"] = "Write a note.";
  errors.value = local;
  failure.value = null;
  if (Object.keys(local).length > 0) return;
  busy.value = true;
  try {
    const r = await resolveUnconfirmed(props.missionId, props.planId, props.pass.snapshot_id, {
      action: action.value,
      note: note.value.trim(),
      ...(booked.value ? { provider_reference: reference.value.trim() } : {}),
    });
    if (r.ok) {
      // #244 (A5): the outcome shows in the sheet; the parent's refresh (which removes this pass's
      // row, and the sheet with it) waits until the person closes it.
      outcome.value = outcomeText(r.value, provider.value);
      resolvedOnClose = true;
      return;
    }
    const f = failureText(r.error, provider.value);
    errors.value = { ...f.fields };
    failure.value = f.text;
    if (f.refresh) emit("resolved");
  } finally {
    busy.value = false;
  }
}
let resolvedOnClose = false;
function onClosed() {
  if (!resolvedOnClose) return;
  resolvedOnClose = false;
  emit("resolved");
}
</script>

<template>
  <!-- Kit ApSheet (focus return, Escape); the first field takes focus, Enter submits. -->
  <ApSheet ref="sheet" :title="title" initial-focus="input, textarea" @closed="onClosed">
    <form class="flex flex-col gap-4" @submit.prevent="submit">
      <ApCallout v-if="outcome" tone="info">{{ outcome }}</ApCallout>
      <ResolveFields
        v-else
        v-model:reference="reference"
        v-model:note="note"
        :booked="booked"
        :provider="provider"
        :errors="errors"
        :failure="failure"
      />
      <!-- The provider re-ask takes seconds (qa: 4-6 s); say what's happening, not just disable. -->
      <p v-if="busy" class="m-0 text-sm text-text-2" role="status">{{ busyText }}</p>
    </form>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">{{
        outcome ? "Close" : "Cancel"
      }}</ApButton>
      <ApButton
        v-if="!outcome"
        :variant="booked ? 'primary' : 'danger'"
        :disabled="busy"
        disabled-reason="Waiting for the provider's answer"
        @click="submit"
        >{{ primary }}</ApButton
      >
    </template>
  </ApSheet>
</template>
