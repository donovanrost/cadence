<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { describeApiError, isError, type ApiError } from "@/api/index.ts";
import { ApButton, ApSheet, ApTextarea } from "@/ui";
import type { Attention } from "./attention.ts";
import {
  CLOSE_BODY,
  NO_ACCESS_JOB,
  closeJob,
  jobWords,
  retryBody,
  retryCheck,
  retryJob,
} from "./jobs.ts";

/**
 * U54 sheets for a job whose outcome is unknown. Retry (danger): the operator ticks that they've
 * checked it didn't happen; Cancel takes the default focus. Close without retry: a required note
 * for the audit. Both answer with the item, which the row or block takes at once.
 */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ done: [item: Attention | null] }>();

const retrySheet = ref<InstanceType<typeof ApSheet> | null>(null);
const closeSheet = ref<InstanceType<typeof ApSheet> | null>(null);
const target = ref<Attention | null>(null);
const checked = ref(false);
const note = ref("");
const error = ref<string | null>(null);
const busy = ref(false);
const noun = computed(() => (target.value ? jobWords(target.value).noun : ""));

function reset(a: Attention) {
  target.value = a;
  checked.value = false;
  note.value = "";
  error.value = null;
}
function openRetry(a: Attention) {
  reset(a);
  retrySheet.value?.open();
}
function openClose(a: Attention) {
  reset(a);
  closeSheet.value?.open();
}

/** 404/409: it closed meanwhile (someone else retried or closed it); the next read shows how. */
function settled(e: ApiError) {
  return e.kind === "not_found" || isError(e, "attention_item_not_open");
}
async function run(kind: "retry" | "close") {
  const a = target.value;
  const text = note.value.trim();
  if (!a || busy.value || (kind === "retry" ? !checked.value : !text)) return;
  busy.value = true;
  error.value = null;
  try {
    const r =
      kind === "retry"
        ? await retryJob(props.missionId, a, text)
        : await closeJob(props.missionId, a, text);
    const sheet = kind === "retry" ? retrySheet.value : closeSheet.value;
    if (r.ok) {
      sheet?.close();
      emit("done", r.value);
    } else if (settled(r.error)) {
      sheet?.close();
      emit("done", null);
    } else if (r.error.kind === "forbidden") error.value = NO_ACCESS_JOB;
    else error.value = describeApiError(r.error);
  } finally {
    busy.value = false;
  }
}
defineExpose({ openRetry, openClose });
</script>

<template>
  <ApSheet ref="retrySheet" title="Retry this job?" width="narrow">
    <p class="m-0 font-semibold text-readout">{{ noun }}</p>
    <p v-if="target" class="m-0 text-md text-text-2">{{ retryBody(target) }}</p>
    <label v-if="target" class="flex items-start gap-2 text-md text-text-2">
      <input
        v-model="checked"
        type="checkbox"
        class="mt-1 accent-[var(--color-readout)] [color-scheme:dark]"
      />
      {{ retryCheck(target) }}
    </label>
    <ApTextarea v-model="note" label="Note" :rows="2" :maxlength="200" />
    <p v-if="error" class="m-0 text-sm text-crit-text">{{ error }}</p>
    <template #footer>
      <ApButton variant="ghost" @click="retrySheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="!checked || busy"
        :disabled-reason="busy ? 'Retrying…' : 'Tick that you checked first.'"
        @click="run('retry')"
        >Retry</ApButton
      >
    </template>
  </ApSheet>
  <!-- a11y A1: a danger sheet opens on its safe button (Cancel, first in the footer). -->
  <ApSheet ref="closeSheet" title="Close without retrying?" width="narrow">
    <p class="m-0 font-semibold text-readout">{{ noun }}</p>
    <p class="m-0 text-md text-text-2">{{ CLOSE_BODY }}</p>
    <ApTextarea v-model="note" label="What did you find?" required :maxlength="200" />
    <p v-if="error" class="m-0 text-sm text-crit-text">{{ error }}</p>
    <template #footer>
      <ApButton variant="ghost" @click="closeSheet?.close()">Cancel</ApButton>
      <ApButton
        :disabled="!note.trim() || busy"
        :disabled-reason="busy ? 'Closing…' : 'Say what you found first.'"
        @click="run('close')"
        >Close</ApButton
      >
    </template>
  </ApSheet>
</template>
