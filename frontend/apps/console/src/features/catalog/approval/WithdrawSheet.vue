<script setup lang="ts">
import { computed, ref, useId } from "vue";
import { ApButton, ApCallout, ApSheet, ApTextarea } from "@/ui";
import { WITHDRAW_LINES, type WithdrawFailure } from "./withdraw-words.ts";
import { REASON_MAX } from "./words.ts";

/**
 * E2 (#546; U109 in #615): "Withdraw approval of catalog rev 4?" A required Reason takes focus
 * (A1); the consequence lines describe the dialog. Commit `Withdraw approval` (danger), `Cancel`.
 * The caller does the write and reports a refusal back through `failure`.
 */
const props = defineProps<{ what: string; busy: boolean; failure: WithdrawFailure | null }>();
const emit = defineEmits<{ withdraw: [reason: string] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const reason = ref("");
const linesId = useId();
const counter = computed(() =>
  reason.value.length >= 1800
    ? `${reason.value.length.toLocaleString("en-US")} / ${REASON_MAX.toLocaleString("en-US")}`
    : undefined,
);
const blocked = computed(() =>
  props.busy ? "Withdrawing…" : reason.value.trim() ? null : "Give a reason first.",
);
function open() {
  reason.value = "";
  sheet.value?.open();
}
defineExpose({ open, close: () => sheet.value?.close() });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="`Withdraw approval of ${what}?`"
    width="narrow"
    initial-focus="textarea"
    :described-by="linesId"
  >
    <div :id="linesId" class="flex flex-col gap-2">
      <p v-for="line in WITHDRAW_LINES" :key="line" class="m-0 text-md text-text-2">{{ line }}</p>
    </div>
    <ApTextarea
      v-model="reason"
      label="Reason"
      required
      :maxlength="REASON_MAX"
      :hint="counter"
      :error="failure?.field"
    />
    <ApCallout v-if="failure?.text" tone="crit" role="alert"
      >{{ failure.text }}
      <details v-if="failure.code" class="mt-1 text-sm">
        <summary class="ap-label cursor-pointer">Technical details</summary>
        <p class="m-0 mt-1 font-mono text-xs text-text-3">{{ failure.code }}</p>
      </details>
    </ApCallout>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? undefined"
        @click="emit('withdraw', reason.trim())"
        >Withdraw approval</ApButton
      >
    </template>
  </ApSheet>
</template>
