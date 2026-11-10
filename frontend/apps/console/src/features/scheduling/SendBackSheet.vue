<script setup lang="ts">
import { computed, nextTick, ref } from "vue";
import type { ApiError } from "@/api";
import { ApButton, ApCallout, ApTextarea } from "@/ui";
import { REASON_MAX } from "./api.ts";
import { planErrorText } from "./errors.ts";

/**
 * K1 admin review: send a pending_approval plan back to its author with a comment (api
 * c7c7b277). The plan returns to draft; the reason shows to the author as the latest decision.
 */
const props = defineProps<{ author: string | null; busy: boolean }>();
const emit = defineEmits<{ submit: [reason: string] }>();
const error = defineModel<ApiError | null>("error", { default: null });
const dialog = ref<HTMLDialogElement | null>(null);
const reason = ref("");
const titleId = `ap-sendback-${Math.random().toString(36).slice(2, 9)}`;
const ready = computed(() => reason.value.trim().length > 0);
let opener: HTMLElement | null = null;

function open() {
  error.value = null;
  opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  dialog.value?.showModal();
  void nextTick(() => dialog.value?.querySelector<HTMLElement>("textarea")?.focus());
}
function close() {
  dialog.value?.close();
}
function onClosed() {
  opener?.focus();
  opener = null;
}
defineExpose({ open, close });
</script>

<template>
  <dialog
    ref="dialog"
    :aria-labelledby="titleId"
    aria-modal="true"
    class="m-auto w-[min(560px,calc(100vw-32px))] border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
    @close="onClosed"
  >
    <div class="flex flex-col gap-3 p-5">
      <h2 :id="titleId" class="m-0 font-display text-xl font-semibold tracking-tag uppercase">
        Send back{{ props.author ? ` to ${props.author}` : "" }}
      </h2>
      <p class="m-0 text-base text-text-3">
        The plan returns to draft. Nothing is booked. Your comment is recorded with the decision.
      </p>
      <ApTextarea v-model="reason" label="What should change" :rows="3" :maxlength="REASON_MAX" />
      <ApCallout v-if="error" tone="caution">{{ planErrorText(error) }}</ApCallout>
    </div>
    <footer class="flex items-center justify-end gap-2 border-t border-hairline px-5 py-3">
      <ApButton variant="ghost" @click="close">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="!ready || busy"
        :disabled-reason="busy ? 'Sending back…' : 'Say what should change first.'"
        @click="emit('submit', reason.trim())"
        >Send back</ApButton
      >
    </footer>
  </dialog>
</template>
