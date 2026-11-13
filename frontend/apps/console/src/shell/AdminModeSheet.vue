<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApCallout, ApField, ApSheet } from "@/ui";
import { retryAfterOf, useRetryAfter } from "@/features/auth/retry-after.ts";
import { enterAdminMode } from "./admin-mode.ts";

/**
 * L6 step-up (Auth.md): the password for platform administration. Wrong password says so
 * plainly; a 429 shows the shared live countdown and disables the primary until it ends.
 */
const emit = defineEmits<{ entered: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const password = ref("");
const busy = ref(false);
const wrong = ref(false);
const failed = ref<string | null>(null);
const retry = useRetryAfter();

const reason = computed(
  () =>
    retry.text.value ??
    (password.value === "" ? "Enter your password first." : busy.value ? "Checking…" : null),
);

function open() {
  password.value = "";
  wrong.value = false;
  failed.value = null;
  sheet.value?.open();
}
async function submit() {
  if (reason.value !== null) return;
  busy.value = true;
  wrong.value = false;
  failed.value = null;
  try {
    const outcome = await enterAdminMode(password.value);
    if (outcome.ok) {
      sheet.value?.close();
      emit("entered");
    } else if (outcome.reason === "wrong_password") wrong.value = true;
    else if (outcome.reason === "throttled") retry.block(retryAfterOf(outcome.error) ?? 60);
    // api-ops a3cf61b0: refused before any password check when the account isn't eligible.
    else if (outcome.reason === "forbidden")
      failed.value = "Your account can't use platform administration.";
    else failed.value = "Couldn't reach Cadence. Try again.";
  } finally {
    busy.value = false;
    password.value = "";
  }
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" title="Admin mode" initial-focus="input">
    <p class="m-0 text-base text-text-3">Enter your password to use platform administration.</p>
    <ApCallout v-if="retry.text.value" tone="caution">{{ retry.text.value }}</ApCallout>
    <ApCallout v-else-if="failed" tone="caution">{{ failed }}</ApCallout>
    <form class="m-0" @submit.prevent="submit">
      <ApField
        v-model="password"
        label="Password"
        type="password"
        autocomplete="current-password"
        :error="wrong ? 'That password isn\'t right.' : null"
      />
    </form>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="reason !== null"
        :disabled-reason="reason ?? undefined"
        @click="submit"
        >Enter admin mode</ApButton
      >
    </template>
  </ApSheet>
</template>
