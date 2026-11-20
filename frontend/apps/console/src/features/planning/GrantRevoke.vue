<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, useId } from "vue";
import { fieldErrors } from "@/api";
import { ApButton, ApCallout, ApSheet, ApTextarea } from "@/ui";
import { revokeFailure } from "./grant-refusals.ts";
import { subject } from "./grant-words.ts";
import { grantFailure, revokeGrant, type Grant } from "./grants.ts";

/**
 * L3 Revoke…: ends a grant now (U105: one person, at once, with a reason). #283: never refused for
 * a hash, so none is sent. A widening waiting to replace the grant is withdrawn with it.
 */
const props = defineProps<{ missionId: MissionId }>();
const emit = defineEmits<{ revoked: [said: string] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
// ux a11y A1 exception: the sheet opens on Reason, so the consequence sentence describes the dialog.
const consequence = useId();
const grant = ref<Grant | null>(null);
/** U105: a proposal waiting to replace this grant (`replaces_grant_id`) is withdrawn with it. */
const replacing = ref(false);
/** In a sentence, a nameless service reads U105's form, never its id (ca-ux). */
const who = computed(() => (grant.value ? subject(grant.value) : ""));
const reason = ref("");
const error = ref<string | null>(null);
const failure = ref<string | null>(null);
const busy = ref(false);
const blocked = computed(() =>
  busy.value ? "Revoking…" : reason.value.trim() === "" ? "Give a reason first." : null,
);
function open(g: Grant, withdraws = false) {
  grant.value = g;
  replacing.value = withdraws;
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
      return void emit("revoked", `Revoked. ${who.value} stops acting on its own now.`);
    }
    error.value = fieldErrors(r.error)["reason"] ?? null;
    failure.value = error.value ? null : (revokeFailure(r.error) ?? grantFailure(r.error));
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
        {{ who }} stops acting on its own now. Plans it already submitted stay as they are.
      </p>
      <p v-if="replacing" class="m-0 text-md text-text-2">
        This also withdraws the proposal waiting for approval, so it can't switch automation back on
        later.
      </p>
      <ApTextarea v-model="reason" label="Reason" required :maxlength="2000" :error="error" />
      <ApCallout v-if="failure" tone="crit" role="alert">{{ failure }}</ApCallout>
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
