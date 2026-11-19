<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, useId } from "vue";
import { fieldErrors } from "@/api";
import { ApButton, ApCallout, ApSheet, ApTextarea } from "@/ui";
import { grantFailure, identityName, revokeGrant, type Grant } from "./grants.ts";

/** L3 Revoke…: ends a grant now, with a required reason; sends the sha256 it read (409 if changed). */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ revoked: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
// ux a11y A1 exception: the sheet opens on Reason, so the consequence sentence describes the dialog.
const consequence = useId();
const grant = ref<Grant | null>(null);
const reason = ref("");
const error = ref<string | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
const blocked = computed(() =>
  busy.value ? "Revoking…" : reason.value.trim() === "" ? "Give a reason first." : null,
);
function open(g: Grant) {
  grant.value = g;
  reason.value = "";
  error.value = failure.value = null;
  sheet.value?.open();
}
async function submit() {
  if (!grant.value || blocked.value !== null) return;
  busy.value = true;
  try {
    const r = await revokeGrant(props.missionId, grant.value, reason.value.trim());
    if (r.ok) {
      sheet.value?.close();
      return void emit("revoked");
    }
    error.value = fieldErrors(r.error)["reason"] ?? null;
    failure.value = error.value ? null : grantFailure(r.error);
  } finally {
    busy.value = false;
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet
    ref="sheet"
    title="Revoke grant"
    width="narrow"
    initial-focus="textarea"
    :described-by="consequence"
  >
    <div class="flex flex-col gap-3">
      <p :id="consequence" class="m-0 text-md text-text-2">
        {{ grant ? identityName(grant) : "" }} stops acting on its own now. Plans it already
        submitted stay as they are.
      </p>
      <ApTextarea v-model="reason" label="Reason" required :maxlength="2000" :error="error" />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="danger"
        :disabled="blocked !== null"
        :disabled-reason="blocked ?? undefined"
        @click="submit"
        >Revoke</ApButton
      >
    </template>
  </ApSheet>
</template>
