<script setup lang="ts">
import type { OrganizationId } from "@/api/index.ts";
import { ref } from "vue";
import { useRouter } from "vue-router";
import { ApButton, ApInlineConfirm, ApPanel, formatShort, OutcomeCallout } from "@/ui";
import { adminErrorText, resendInvitation, revokeInvitation } from "./admin.ts";
import { roleLabel, type Invitation } from "./api.ts";

/**
 * Invitation details with Resend (moves to the new id; old link dead) and Revoke, confirmed in
 * place with the kit's ApInlineConfirm (O5, design-language §7).
 */
const props = defineProps<{ orgId: OrganizationId; invitation: Invitation; canManage: boolean }>();
const emit = defineEmits<{ changed: []; moving: [to: string] }>();
const router = useRouter();
const busy = ref(false);
const confirming = ref(false);
const refusal = ref<string | null>(null);
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
      emit("moving", r.value.id);
      await router.replace({ name: "org.people.invitation", params: { invitationId: r.value.id } });
    } else note.value = { tone: "caution", text: adminErrorText(r.error) };
    emit("changed");
  } finally {
    busy.value = false;
  }
}

async function revoke() {
  busy.value = true;
  refusal.value = null;
  try {
    const r = await revokeInvitation(props.orgId, props.invitation.id);
    if (r.ok) return void router.push({ name: "org.people" });
    refusal.value = adminErrorText(r.error);
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
        ><template v-if="invitation.status !== 'pending'"> · {{ invitation.status }}</template>
      </p>
      <OutcomeCallout v-if="note" :outcome="note" />
      <div v-if="canManage" class="flex flex-wrap items-center gap-3">
        <ApButton :disabled="busy" disabled-reason="Working…" @click="resend">Resend</ApButton>
        <ApInlineConfirm
          v-model:open="confirming"
          action="Revoke invitation"
          :busy="busy"
          busy-reason="Revoking…"
          :refusal="refusal"
          @confirm="revoke"
          @cancel="refusal = null"
        >
          <template #trigger="{ attrs }">
            <ApButton variant="ghost" v-bind="attrs">Revoke…</ApButton>
          </template>
          Revoke the invitation to {{ invitation.email }}? Its link stops working.
        </ApInlineConfirm>
      </div>
      <p v-else class="m-0 text-sm text-text-3">Org admins manage access.</p>
    </div>
  </ApPanel>
</template>
