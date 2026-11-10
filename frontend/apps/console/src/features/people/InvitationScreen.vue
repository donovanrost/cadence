<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import {
  ApBreadcrumb,
  ApButton,
  ApCallout,
  ApEmptyState,
  ApPanel,
  ApRemote,
  formatShort,
} from "@/ui";
import { adminErrorText, resendInvitation, revokeInvitation } from "./admin.ts";
import { fetchPeople, roleLabel } from "./api.ts";

/** People.md Invitations: the email link's detail, with Resend / Revoke (O5, org admins). */
const scope = useConsoleScope();
const route = useRoute();
const router = useRouter();
const org = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const id = computed(() => String(route.params["invitationId"] ?? ""));
const { state, refetch } = useRemoteQuery(() => org.value?.id ?? null, fetchPeople);
const invitation = computed(() =>
  state.value.status === "ready"
    ? (state.value.value.invitations.find((i) => i.id === id.value) ?? null)
    : null,
);
const canManage = computed(
  () =>
    state.value.status === "ready" && state.value.value.permissions.includes("org.manage_members"),
);
const busy = ref(false);
const confirming = ref(false);
const note = ref<{ tone: "nominal" | "caution"; text: string } | null>(null);

async function resend() {
  if (!org.value || !invitation.value) return;
  busy.value = true;
  try {
    const r = await resendInvitation(org.value.id, invitation.value.id);
    if (r.ok) {
      note.value = {
        tone: "nominal",
        text: `Sent again to ${invitation.value.email}. The old link no longer works.`,
      };
      await router.replace({ name: "org.people.invitation", params: { invitationId: r.value.id } });
    } else note.value = { tone: "caution", text: adminErrorText(r.error) };
    refetch();
  } finally {
    busy.value = false;
  }
}

async function revoke() {
  if (!org.value || !invitation.value) return;
  busy.value = true;
  try {
    const r = await revokeInvitation(org.value.id, invitation.value.id);
    if (r.ok) return void router.push({ name: "org.people" });
    note.value = { tone: "caution", text: adminErrorText(r.error) };
    refetch();
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="mx-auto flex w-full max-w-[900px] flex-col gap-4">
    <ApBreadcrumb
      :crumbs="[
        { label: 'People & access', to: { name: 'org.people' } },
        { label: invitation?.email ?? 'Invitation', literal: true },
      ]"
    />
    <ApRemote :state="state" loading-label="Loading invitation…" @retry="refetch">
      <ApEmptyState
        v-if="!invitation"
        state="off"
        headline="This invitation isn't pending"
        sentence="It was accepted, revoked or replaced by a resend. Open People & access for the current list."
      />
      <ApPanel v-else index="I1" :title="`Invitation · ${invitation.email}`">
        <div class="flex flex-col gap-4">
          <p class="m-0 text-md text-text-2">
            {{ roleLabel(invitation.role) }} · invited by
            {{ invitation.invited_by?.name ?? "someone" }} · sent
            <span class="font-mono">{{ formatShort(new Date(invitation.sent_at)) }}</span
            ><template v-if="invitation.expires_at">
              · expires
              <span class="font-mono">{{
                formatShort(new Date(invitation.expires_at))
              }}</span></template
            ><template v-if="invitation.status === 'expired'"> · expired</template>
          </p>
          <ApCallout v-if="note" :tone="note.tone">{{ note.text }}</ApCallout>
          <div v-if="canManage" class="flex flex-wrap items-center gap-3">
            <ApButton :disabled="busy" disabled-reason="Working…" @click="resend">Resend</ApButton>
            <ApButton v-if="!confirming" variant="ghost" @click="confirming = true"
              >Revoke…</ApButton
            >
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
    </ApRemote>
  </div>
</template>
