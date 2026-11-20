<script setup lang="ts">
import { ref } from "vue";
import { RetryAfterNotice, retryAfterOf, useRetryAfter } from "@/features/auth/index.ts";
import { ApButton, ApCallout, ApField, ApPanel, outcomeRole } from "@/ui";
import { changePassword, passwordFailure, passwordProblems, PASSWORD_MIN } from "./api.ts";

/** People.md Account · password change (current + new + confirm). Other sessions sign out. */
const emit = defineEmits<{ changed: [] }>();
const current = ref("");
const next = ref("");
const confirm = ref("");
const errors = ref<Record<string, string>>({});
const note = ref<{ tone: "nominal" | "caution"; text: string } | null>(null);
const busy = ref(false);
/** Auth.md: one 429 state for every password field, a live countdown that re-enables at zero. */
const retry = useRetryAfter();

async function save() {
  errors.value = passwordProblems(current.value, next.value, confirm.value);
  note.value = null;
  if (Object.keys(errors.value).length > 0 || busy.value || retry.blocked.value) return;
  busy.value = true;
  try {
    const r = await changePassword({ current_password: current.value, new_password: next.value });
    if (r.ok) {
      current.value = next.value = confirm.value = "";
      note.value = {
        tone: "nominal",
        text: "Password changed. Your other sessions were signed out; this one stays signed in.",
      };
      emit("changed");
      return;
    }
    const wait = retryAfterOf(r.error);
    if (wait !== null) return void retry.block(wait);
    const f = passwordFailure(r.error);
    errors.value = f.fields;
    if (f.text) note.value = { tone: "caution", text: f.text };
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="A3" title="Password">
    <form class="flex max-w-[420px] flex-col gap-4" @submit.prevent="save">
      <ApField
        v-model="current"
        label="Current password"
        type="password"
        autocomplete="current-password"
        :error="errors['current'] ?? null"
      />
      <ApField
        v-model="next"
        label="New password"
        type="password"
        autocomplete="new-password"
        :hint="`At least ${PASSWORD_MIN} characters.`"
        :error="errors['next'] ?? null"
      />
      <ApField
        v-model="confirm"
        label="Confirm new password"
        type="password"
        autocomplete="new-password"
        :error="errors['confirm'] ?? null"
      />
      <RetryAfterNotice :retry="retry" />
      <ApCallout
        v-if="!retry.text.value && note"
        :tone="note.tone"
        :role="outcomeRole(note.tone)"
        >{{ note.text }}</ApCallout
      >
      <div>
        <ApButton
          type="submit"
          variant="primary"
          :disabled="busy || retry.blocked.value"
          :disabled-reason="retry.text.value ?? 'Changing…'"
          >Change password</ApButton
        >
      </div>
    </form>
  </ApPanel>
</template>
