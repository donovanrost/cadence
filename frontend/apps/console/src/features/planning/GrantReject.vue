<script setup lang="ts">
import { ref, useId } from "vue";
import { ApButton, ApSheet, ApTextarea } from "@/ui";
import GrantRefusal from "./GrantRefusal.vue";
import type { Worded } from "./grant-words.ts";

/**
 * U105 Reject…: a reason is required ("Give a reason first.", A7); the 422 field message shows
 * under the field. The caller writes and reports back through `error` / `refusal`.
 */
defineProps<{
  service: string | null;
  busy: boolean;
  error: string | null;
  refusal: Worded | null;
}>();
const emit = defineEmits<{ reject: [reason: string] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
// ux a11y A1 exception: the sheet opens on Reason, so its consequence describes the dialog.
const consequence = useId();
const reason = ref("");
function open() {
  reason.value = "";
  sheet.value?.open();
}
defineExpose({ open, close: () => sheet.value?.close() });
</script>

<template>
  <ApSheet
    ref="sheet"
    title="Reject the proposed grant"
    width="narrow"
    initial-focus="textarea"
    :described-by="consequence"
  >
    <div class="flex flex-col gap-3">
      <p :id="consequence" class="m-0 text-md text-text-2">
        {{ service ?? "The service identity this grant is for" }} won't act under this grant. To try
        again, propose a new grant.
      </p>
      <ApTextarea v-model="reason" label="Reason" required :maxlength="2000" :error="error" />
      <GrantRefusal :refusal="refusal" />
    </div>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="!reason.trim() || busy"
        :disabled-reason="busy ? 'Rejecting…' : 'Give a reason first.'"
        @click="emit('reject', reason.trim())"
        >Reject</ApButton
      >
    </template>
  </ApSheet>
</template>
