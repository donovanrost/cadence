<script setup lang="ts">
import { computed, ref, useId } from "vue";
import { ApButton, ApCallout, ApSheet, ApTextarea } from "@/ui";

/** A confirm with a required reason (L13 revokes). The caller runs the write and reports back. */
defineProps<{ title: string; sentence: string; confirm: string }>();
const emit = defineEmits<{ confirm: [reason: string] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
// ux a11y A1 exception: the sheet opens on Reason, so the consequence sentence describes the dialog.
const consequence = useId();
const reason = ref("");
const failure = ref<string | null>(null);
const busy = ref(false);
const blocked = computed(() =>
  busy.value ? "Working…" : reason.value.trim() === "" ? "Give a reason first." : null,
);
function open() {
  reason.value = "";
  failure.value = null;
  busy.value = false;
  sheet.value?.open();
}
/** The caller's answer: null closes the sheet, a sentence shows as the failure. */
function settle(error: string | null) {
  busy.value = false;
  if (error === null) sheet.value?.close();
  else failure.value = error;
}
function submit() {
  if (blocked.value !== null) return;
  busy.value = true;
  emit("confirm", reason.value.trim());
}
defineExpose({ open, settle });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="title"
    width="narrow"
    initial-focus="textarea"
    :described-by="consequence"
  >
    <div class="flex flex-col gap-3">
      <p :id="consequence" class="m-0 text-md text-text-2">{{ sentence }}</p>
      <ApTextarea v-model="reason" label="Reason" required :maxlength="2000" />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? undefined"
        @click="submit"
        >{{ confirm }}</ApButton
      >
    </template>
  </ApSheet>
</template>
