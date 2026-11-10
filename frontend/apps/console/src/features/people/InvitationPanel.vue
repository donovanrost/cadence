<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { ApButton, ApCallout, ApPanel, formatShort } from "@/ui";
import { adminErrorText, resendInvitation, revokeInvitation } from "./admin.ts";
import { roleLabel, type Invitation } from "./api.ts";

/** Invitation details with Resend (moves to the new id; old link dead) and a two-step Revoke (O5). */
const props = defineProps<{ orgId: string; invitation: Invitation; canManage: boolean }>();
const emit = defineEmits<{ changed: [] }>();
const router = useRouter();
const busy = ref(false);
const confirming = ref(false);
const note = ref<{ tone: "nominal" | "caution"; text: string } | null>(null);
const when = (iso: string) => formatShort(new Date(iso));

async function resend() {
  busy.value = true;
  try {
    const r = await resendInvitation(props.orgId, props.invitation.id);
    if (r.ok) {
      note.value = {
        tone: "nominal",
        text: `Sent again to ${props.invitation.email}. The old link no longer works.`,
      };
      await router.replace({ name: "org.people.invitation", params: { invitationId: r.value.id } });
    } else note.value = { tone: "caution", text: adminErrorText(r.error) };
    emit("changed");
  } finally {
    busy.value = false;
  }
}

async function revoke() {
  busy.value = true;
  try {
    const r = await revokeInvitation(props.orgId, props.invitation.id);
    if (r.ok) return void router.push({ name: "org.people" });
    note.value = { tone: "caution", text: adminErrorText(r.error) };
    emit("changed");
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="I1" title="Details">
    <div class="flex flex-col gap-4">
      <p class="m-0 text-md text-text-2">
        {{ roleLabel(invitation.role) }} · invited by
        {{ invitation.invited_by?.name ?? "someone" }} · sent
        <span class="font-mono">{{ when(invitation.sent_at) }}</span
        ><template v-if="invitation.expires_at">
          · expires <span class="font-mono">{{ when(invitation.expires_at) }}</span></template
        ><template v-if="invitation.status === 'expired'"> · expired</template>
      </p>
      <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
      <div v-if="canManage" class="flex flex-wrap items-center gap-3">
        <ApButton :disabled="busy" disabled-reason="Working…" @click="resend">Resend</ApButton>
        <ApButton v-if="!confirming" variant="ghost" @click="confirming = true">Revoke…</ApButton>
        <template v-else>
          <ApButton variant="danger" :disabled="busy" disabled-reason="Working…" @click="revoke"
            >Revoke the invitation</ApButton
          >
          <ApButton variant="ghost" @click="confirming = false">Cancel</ApButton>
        </template>
      </div>
      <p v-else class="m-0 text-sm text-text-3">Org admins manage access.</p>
    </div>
  </ApPanel>
</template>
