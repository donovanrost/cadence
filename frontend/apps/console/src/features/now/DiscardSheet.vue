<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { describeApiError, isError } from "@/api/index.ts";
import { ApButton, ApSheet, ApTextarea } from "@/ui";
import type { Attention } from "./attention.ts";
import {
  DISCARD_BODY,
  DISCARD_DETAIL,
  NO_ACCESS_ARCHIVE,
  discardArchive,
  discardTitle,
} from "./archive.ts";

/**
 * U49 Discard…: records the archive couldn't take, discarded with a required reason (resolve's
 * action_text, ≤ 200). "May still be in the buffer" is a may, so it sits in Technical details (U20).
 */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ done: [item: Attention | null] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const target = ref<Attention | null>(null);
const reason = ref("");
const error = ref<string | null>(null);
const busy = ref(false);
const title = computed(() => (target.value ? discardTitle(target.value) : "Discard"));

function open(a: Attention) {
  target.value = a;
  reason.value = "";
  error.value = null;
  sheet.value?.open();
}
async function discard() {
  const a = target.value;
  const text = reason.value.trim();
  if (!a || busy.value || !text) return;
  busy.value = true;
  error.value = null;
  try {
    const r = await discardArchive(props.missionId, a, text);
    if (r.ok) {
      sheet.value?.close();
      emit("done", r.value);
    } else if (r.error.kind === "not_found") {
      // It closed meanwhile (archived on retry, or someone discarded it): the next read shows it.
      sheet.value?.close();
      emit("done", null);
    } else if (r.error.kind === "forbidden") error.value = NO_ACCESS_ARCHIVE;
    else if (isError(r.error, "reason_required")) error.value = "Give a reason first.";
    else error.value = describeApiError(r.error);
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <!-- a11y A1: a danger sheet opens on its safe button (Cancel, first in the footer). -->
  <ApSheet ref="sheet" :title="title" width="narrow">
    <p class="m-0 text-md text-text-2">{{ DISCARD_BODY }}</p>
    <ApTextarea v-model="reason" label="Reason" required :maxlength="200" />
    <p v-if="error" class="m-0 text-sm text-crit-text">{{ error }}</p>
    <details class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p class="m-0 pt-1">{{ DISCARD_DETAIL }}</p>
      <p v-if="target" class="m-0 font-mono break-all">id: {{ target.id }}</p>
    </details>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="!reason.trim() || busy"
        :disabled-reason="busy ? 'Discarding…' : 'Give a reason first.'"
        @click="discard"
        >Discard</ApButton
      >
    </template>
  </ApSheet>
</template>
