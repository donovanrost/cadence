<script setup lang="ts">
import { ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { ApButton } from "@/ui";
import {
  acceptInvitation,
  declineInvitation,
  invitationFailure,
  invitationLine,
  type MyInvitation,
} from "./invitations.ts";

/** One pending invitation: Accept opens the org; Decline confirms first (People.md Account). */
const props = defineProps<{ invitation: MyInvitation }>();
/** `failed`: the act was refused or failed, so the parent says it as an alert (B6, ux #276). */
const emit = defineEmits<{ changed: [note: string | null, failed: boolean] }>();
const confirming = ref(false);
const busy = ref(false);

async function accept() {
  busy.value = true;
  try {
    const r = await acceptInvitation(props.invitation.id);
    // The session is a boot snapshot: a full load re-bootstraps, so the switcher shows the org (lead).
    if (r.ok)
      return void window.location.assign(
        `/console/${encodeURIComponent(r.value.organization.slug)}`,
      );
    emit(
      "changed",
      invitationFailure(r.error) ?? failureOutcome(r.error, "changed").sentence,
      true,
    );
  } finally {
    busy.value = false;
  }
}

async function decline() {
  busy.value = true;
  try {
    const r = await declineInvitation(props.invitation.id);
    emit(
      "changed",
      r.ok
        ? `Declined the invitation to ${props.invitation.organization.name}.`
        : (invitationFailure(r.error) ?? failureOutcome(r.error, "changed").sentence),
      !r.ok,
    );
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <li class="flex flex-wrap items-center gap-3 border-t border-hairline px-4 py-3 first:border-t-0">
    <span class="min-w-0 flex-1 text-md text-readout">{{ invitationLine(invitation) }}</span>
    <template v-if="!confirming">
      <ApButton
        variant="primary"
        size="compact"
        :disabled="busy"
        disabled-reason="Working…"
        @click="accept"
        >Accept</ApButton
      >
      <ApButton
        variant="ghost"
        size="compact"
        :disabled="busy"
        disabled-reason="Working…"
        @click="confirming = true"
        >Decline…</ApButton
      >
    </template>
    <template v-else>
      <ApButton
        variant="danger"
        size="compact"
        :disabled="busy"
        disabled-reason="Working…"
        @click="decline"
        >Decline the invitation</ApButton
      >
      <ApButton variant="ghost" size="compact" @click="confirming = false">Keep it</ApButton>
    </template>
  </li>
</template>
