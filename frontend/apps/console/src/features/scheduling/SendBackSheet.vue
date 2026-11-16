<script setup lang="ts">
import { computed, ref } from "vue";
import type { ApiError } from "@/api";
import { ApButton, ApCallout, ApSheet, ApTextarea } from "@/ui";
import { REASON_MAX } from "./api.ts";
import { planErrorText } from "./errors.ts";

/**
 * K1 admin review: send a pending_approval plan back to its author with a comment (api
 * c7c7b277). The plan returns to draft; the reason shows to the author as the latest decision.
 */
const props = defineProps<{ author: string | null; busy: boolean }>();
const emit = defineEmits<{ submit: [reason: string] }>();
const error = defineModel<ApiError | null>("error", { default: null });
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const reason = ref("");
const ready = computed(() => reason.value.trim().length > 0);

function open() {
  error.value = null;
  sheet.value?.open();
}
function close() {
  sheet.value?.close();
}
defineExpose({ open, close });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="`Send back${props.author ? ` to ${props.author}` : ''}`"
    initial-focus="textarea"
  >
    <p class="m-0 text-base text-text-3">
      The plan returns to draft. Nothing is booked. Your comment is recorded with the decision.
    </p>
    <ApTextarea
      v-model="reason"
      label="What should change"
      :rows="3"
      :maxlength="REASON_MAX"
      required
    />
    <ApCallout v-if="error" tone="caution">{{ planErrorText(error) }}</ApCallout>
    <template #footer>
      <ApButton variant="ghost" @click="close">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="!ready || busy"
        :disabled-reason="busy ? 'Sending back…' : 'Say what should change first.'"
        @click="emit('submit', reason.trim())"
        >Send back</ApButton
      >
    </template>
  </ApSheet>
</template>
