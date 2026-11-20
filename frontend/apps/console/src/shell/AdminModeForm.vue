<script setup lang="ts">
import RetryAfterNotice from "@/features/auth/RetryAfterNotice.vue";
import { computed, ref } from "vue";
import { ApButton, ApCallout, ApField } from "@/ui";
import { retryAfterOf, useRetryAfter } from "@/features/auth/retry-after.ts";
import { enterAdminMode } from "./admin-mode.ts";

/**
 * L6 step-up (Auth.md): the password for platform administration, as a form on its own, used by
 * AdminModeSheet and inline on admin pages outside admin mode (Admin.md, fe-setup L7). A wrong
 * password says so plainly; a 429 shows the shared live countdown and disables the primary.
 */
const emit = defineEmits<{ entered: [] }>();
defineSlots<{ actions?(): unknown }>();
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

function reset() {
  password.value = "";
  wrong.value = false;
  failed.value = null;
}
async function submit() {
  if (reason.value !== null) return;
  busy.value = true;
  wrong.value = false;
  failed.value = null;
  try {
    const outcome = await enterAdminMode(password.value);
    if (outcome.ok) emit("entered");
    else if (outcome.reason === "wrong_password") wrong.value = true;
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
defineExpose({ reset });
</script>

<template>
  <form class="m-0 flex flex-col gap-3" @submit.prevent="submit">
    <p class="m-0 text-base text-text-3">Enter your password to use platform administration.</p>
    <RetryAfterNotice :retry="retry" />
    <ApCallout v-if="!retry.text.value && failed" tone="caution" role="alert">{{
      failed
    }}</ApCallout>
    <ApField
      v-model="password"
      label="Password"
      type="password"
      autocomplete="current-password"
      :error="wrong ? 'That password isn\'t right.' : null"
    />
    <div class="flex flex-wrap items-center justify-end gap-2">
      <slot name="actions" />
      <ApButton
        variant="primary"
        type="submit"
        :disabled="reason !== null"
        :disabled-reason="reason ?? undefined"
        >Enter admin mode</ApButton
      >
    </div>
  </form>
</template>
