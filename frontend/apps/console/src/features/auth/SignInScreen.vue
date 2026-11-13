<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import { describeApiError, isError } from "@/api";
import { ApButton, ApCallout, ApField } from "@/ui";
import { goTo, optionalSession, safeReturn, signIn } from "./api.ts";
import { retryAfterOf, useRetryAfter } from "./retry-after.ts";
import { UNREACHABLE, WRONG_CREDENTIALS } from "./words.ts";

/**
 * Sign in (ux Auth.md): email + password, one path. Success follows the server's redirect_to (it
 * validates return_to) with a full navigation; someone already signed in goes straight there.
 * Errors never say which part was wrong; 429 counts down and re-enables.
 */
const route = useRoute();
const returnTo = computed(() => safeReturn(route.query.return_to));
const email = ref("");
const password = ref("");
const busy = ref(false);
const error = ref<{ tone: "crit" | "caution"; text: string } | null>(null);
const retry = useRetryAfter();

onMounted(async () => {
  const s = await optionalSession();
  if (s.ok && s.value) goTo(returnTo.value ?? "/console/");
});

async function submit() {
  if (busy.value || retry.blocked.value) return;
  busy.value = true;
  error.value = null;
  const r = await signIn(email.value.trim(), password.value, returnTo.value);
  busy.value = false;
  if (r.ok) return goTo(r.value.redirect_to);
  const wait = retryAfterOf(r.error);
  if (wait !== null) return retry.block(wait);
  error.value = isError(r.error, "credentials_incorrect")
    ? { tone: "crit", text: WRONG_CREDENTIALS }
    : {
        tone: "caution",
        text:
          r.error.kind === "unavailable" && r.error.message
            ? `${UNREACHABLE} (${describeApiError(r.error)})`
            : UNREACHABLE,
      };
}
const reason = computed(() => retry.text.value ?? (busy.value ? "Signing in…" : null));
</script>

<template>
  <div class="flex flex-col gap-4">
    <h1 class="m-0 font-display text-[24px] font-semibold tracking-head uppercase">Sign in</h1>
    <ApCallout v-if="retry.text.value" tone="caution">{{ retry.text.value }}</ApCallout>
    <ApCallout v-else-if="error" :tone="error.tone">{{ error.text }}</ApCallout>
    <form class="flex flex-col gap-3" @submit.prevent="submit">
      <ApField v-model="email" label="Email" type="email" autocomplete="username" required />
      <ApField
        v-model="password"
        label="Password"
        type="password"
        autocomplete="current-password"
        required
      />
      <ApButton
        type="submit"
        variant="primary"
        class="w-full"
        :disabled="reason !== null"
        :disabled-reason="reason ?? undefined"
        >Sign in</ApButton
      >
    </form>
  </div>
</template>
