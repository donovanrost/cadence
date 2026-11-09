<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import { ApButton, ApCallout } from "@/ui";
import ResolveFields from "./ResolveFields.vue";
import { failureText, outcomeText, resolveUnconfirmed, type ResolveAction } from "./api.ts";
import type { ResolvablePass } from "./types.ts";

/**
 * ux U32 sheets: Mark booked / Mark not booked for one unconfirmed pass. Cadence re-asks the
 * provider first; the outcome replaces the form, and `resolved` tells the screen to refetch.
 */
const props = defineProps<{ missionId: string; planId: string; pass: ResolvablePass }>();
const emit = defineEmits<{ resolved: [] }>();

const action = ref<ResolveAction>("booked");
const note = ref("");
const reference = ref("");
const errors = ref<Record<string, string>>({});
const failure = ref<string | null>(null);
const outcome = ref<string | null>(null);
const busy = ref(false);
const dialog = ref<HTMLDialogElement | null>(null);
const titleId = `ap-resolve-${Math.random().toString(36).slice(2, 9)}`;

const provider = computed(() => props.pass.provider.name ?? "the provider");
const booked = computed(() => action.value === "booked");
const title = computed(
  () => `Mark ${props.pass.text} as ${booked.value ? "booked" : "not booked"}`,
);
const primary = computed(() =>
  booked.value ? "Mark booked" : `Cancel at ${provider.value} and mark not booked`,
);

let opener: HTMLElement | null = null;
function open(next: ResolveAction) {
  action.value = next;
  note.value = "";
  reference.value = "";
  errors.value = {};
  failure.value = null;
  outcome.value = null;
  opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  dialog.value?.showModal();
  void nextTick(() => dialog.value?.querySelector<HTMLElement>("input, textarea")?.focus());
}
function onClosed() {
  opener?.focus();
  opener = null;
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
      outcome.value = outcomeText(r.value, provider.value);
      emit("resolved");
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
</script>

<template>
  <dialog
    ref="dialog"
    :aria-labelledby="titleId"
    aria-modal="true"
    class="m-auto w-[min(560px,calc(100vw-32px))] border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
    @close="onClosed"
  >
    <form class="flex flex-col gap-4 p-5" @submit.prevent="submit">
      <h2 :id="titleId" class="m-0 font-display text-xl font-semibold tracking-tag uppercase">
        {{ title }}
      </h2>
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
      <footer class="flex items-center justify-end gap-3 border-t border-hairline pt-3">
        <ApButton variant="ghost" @click="dialog?.close()">{{
          outcome ? "Close" : "Cancel"
        }}</ApButton>
        <ApButton
          v-if="!outcome"
          type="submit"
          :variant="booked ? 'primary' : 'danger'"
          :disabled="busy"
          disabled-reason="Asking the provider…"
          >{{ primary }}</ApButton
        >
      </footer>
    </form>
  </dialog>
</template>
