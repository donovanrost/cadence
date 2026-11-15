<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApSheet, ApTextarea } from "@/ui";
import { REASON_MAX } from "./words.ts";

/**
 * ux U65 Reject confirm: required reason; Cancel is the default. The caller does the write and
 * reports a refusal back through `error`.
 */
const props = defineProps<{ rev: number | null; busy: boolean; error: string | null }>();
const emit = defineEmits<{ reject: [reason: string] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const reason = ref("");
/** ux U65: a counter from 1,800 characters (the limit is 2,000). */
const counter = computed(() =>
  reason.value.length >= 1800
    ? `${reason.value.length.toLocaleString("en-US")} / ${REASON_MAX.toLocaleString("en-US")}`
    : undefined,
);
const label = () => (props.rev === null ? "this revision" : `rev ${props.rev}`);

function open() {
  reason.value = "";
  sheet.value?.open();
}
defineExpose({ open, close: () => sheet.value?.close() });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="rev === null ? 'Reject this catalog revision?' : `Reject catalog rev ${rev}?`"
    width="narrow"
    initial-focus="textarea"
  >
    <p class="m-0 text-md text-text-2">
      Spacecraft can't move to {{ label() }} after this. To try again, import a new revision.
    </p>
    <ApTextarea v-model="reason" label="Reason" required :maxlength="REASON_MAX" :hint="counter" />
    <p v-if="error" class="m-0 text-sm text-crit-text">{{ error }}</p>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="!reason.trim() || busy"
        :disabled-reason="busy ? 'Rejecting…' : 'Give a reason first.'"
        @click="emit('reject', reason.trim())"
        >Reject {{ label() }}</ApButton
      >
    </template>
  </ApSheet>
</template>
