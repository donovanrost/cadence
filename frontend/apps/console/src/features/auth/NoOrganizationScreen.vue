<script setup lang="ts">
import { onMounted, ref, shallowRef } from "vue";
import { useRemoteQuery, describeApiError } from "@/api";
import type { Session } from "@/api/session.ts";
import { ApButton, ApCallout } from "@/ui";
import InvitationRow from "@/features/account/InvitationRow.vue";
import AdminModeSheet from "@/shell/AdminModeSheet.vue";
import { fetchMyInvitations } from "@/features/account/invitations.ts";
import { goTo, optionalSession, signOutHere } from "./api.ts";

/**
 * No organization (ux Auth.md): signed in, member of none. Pending invitations are Account's rows
 * (L21: Accept opens the org, Decline confirms); without any, who to ask, with Sign out. Platform
 * admins also get Enter admin mode. Signed out here means sign in first.
 */
const session = shallowRef<Session | null>(null);
const failed = ref<string | null>(null);
onMounted(async () => {
  const s = await optionalSession();
  if (!s.ok) failed.value = describeApiError(s.error);
  else if (s.value === null)
    goTo(`/console/sign-in?return_to=${encodeURIComponent("/console/no-organization")}`);
  else session.value = s.value;
});
const list = useRemoteQuery(() => (session.value ? (true as const) : null), fetchMyInvitations);
const note = ref<string | null>(null);
/** L6 (lead): the shell's step-up sheet works without AppShell; then the admin area (L7: /admin). */
const adminSheet = ref<InstanceType<typeof AdminModeSheet> | null>(null);
const adminOn = ref(false);
function changed(text: string | null) {
  note.value = text;
  list.refetch();
}
</script>

<template>
  <div class="flex flex-col gap-4">
    <ApCallout v-if="failed" tone="caution">{{ failed }}</ApCallout>
    <p
      v-else-if="!session || list.state.value.status === 'loading'"
      class="m-0 font-mono text-sm text-text-3"
      role="status"
    >
      Loading…
    </p>
    <template v-else>
      <ApCallout v-if="note" tone="info">{{ note }}</ApCallout>
      <template v-if="list.state.value.status === 'ready' && list.state.value.value.length > 0">
        <h1 class="m-0 font-display text-[24px] font-semibold tracking-head uppercase">
          You have {{ list.state.value.value.length }}
          {{ list.state.value.value.length === 1 ? "invitation" : "invitations" }}
        </h1>
        <ul class="m-0 list-none border border-hairline p-0">
          <InvitationRow
            v-for="i in list.state.value.value"
            :key="i.id"
            :invitation="i"
            @changed="changed"
          />
        </ul>
      </template>
      <template v-else>
        <h1 class="m-0 font-display text-[24px] font-semibold tracking-head uppercase">
          You're not in an organization yet
        </h1>
        <p class="m-0 text-text-2">
          Ask an organization admin to invite you. They'll need your email:
          {{ session.user.email }}.
        </p>
      </template>
      <template v-if="session.platform_admin_eligible">
        <ApButton v-if="adminOn" variant="secondary" class="w-full" @click="goTo('/admin')"
          >Admin area</ApButton
        >
        <ApButton v-else variant="secondary" class="w-full" @click="adminSheet?.open()"
          >Enter admin mode</ApButton
        >
        <AdminModeSheet ref="adminSheet" @entered="adminOn = true" />
      </template>
      <ApButton variant="ghost" class="w-full" @click="signOutHere(session.csrf_token)"
        >Sign out</ApButton
      >
    </template>
  </div>
</template>
