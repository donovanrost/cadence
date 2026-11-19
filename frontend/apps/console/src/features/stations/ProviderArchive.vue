<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref, useId } from "vue";
import { ApButton, ApSheet, ApTextarea } from "@/ui";
import { archiveProvider, providerFailure } from "./providers.ts";

/** L12 Archive…: required reason; bookings already made keep the provider's version. */
const props = defineProps<{ missionId: MissionId; providerId: string }>();
const emit = defineEmits<{ done: [note: { tone: "nominal" | "crit"; text: string }] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
// ux a11y A1 exception: the sheet opens on Reason, so the consequence sentence describes the dialog.
const consequence = useId();
const reason = ref("");
const busy = ref(false);
function open() {
  reason.value = "";
  sheet.value?.open();
}
async function archive() {
  if (busy.value || !reason.value.trim()) return;
  busy.value = true;
  try {
    const r = await archiveProvider(props.missionId, props.providerId, reason.value.trim());
    sheet.value?.close();
    emit(
      "done",
      r.ok
        ? {
            tone: "nominal",
            text: "Archived. Bookings already made keep it; new ones can't use it.",
          }
        : { tone: "crit", text: providerFailure(r.error) },
    );
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet
    ref="sheet"
    title="Archive provider"
    width="narrow"
    initial-focus="textarea"
    :described-by="consequence"
  >
    <p :id="consequence" class="m-0 text-md text-text-2">
      Bookings already made keep this provider's version; no new ones can use it.
    </p>
    <ApTextarea v-model="reason" label="Reason" required :maxlength="2000" />
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="!reason.trim() || busy"
        :disabled-reason="busy ? 'Archiving…' : 'Give a reason first.'"
        @click="archive"
        >Archive</ApButton
      >
    </template>
  </ApSheet>
</template>
