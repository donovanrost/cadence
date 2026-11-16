<script setup lang="ts">
import { computed, ref } from "vue";
import { ApMenuButton, ApMenuItem, initials, useNow } from "@/ui";
import AdminModeSheet from "./AdminModeSheet.vue";
import { leaveAdminMode, useAdminMode } from "./admin-mode.ts";
import { hasCapability, useSession } from "./session.ts";

const session = useSession();

const name = computed(() => session.user.display_name ?? session.user.email);
const otherOrganizations = computed(() =>
  session.organizations.filter((org) => org.missions.length > 0),
);
/** L6: eligible admins step up from here; while on, the menu offers the area and Leave. */
const eligible = computed(
  () => session.platform_admin_eligible || hasCapability(session, "platform_admin"),
);
const invitations = computed(() => session.pending_invitations_count ?? 0);
const now = useNow();
const admin = useAdminMode(() => now.value);
const adminSheet = ref<InstanceType<typeof AdminModeSheet> | null>(null);
/** The kit menu has already closed and handed focus back to the trigger (design-language §6). */
function enterAdmin() {
  adminSheet.value?.open();
}
function leaveAdmin() {
  void leaveAdminMode();
}
</script>

<template>
  <ApMenuButton
    class="ml-auto flex border-l border-hairline"
    :label="`${initials(name)}, account menu for ${name}`"
    :menu-label="`Account menu for ${name}`"
    trigger-class="w-[52px] cursor-pointer border-0 bg-transparent font-display text-base font-semibold tracking-[.1em] text-readout hover:bg-raised"
    menu-class="min-w-[260px]"
  >
    <template #trigger>{{ initials(name) }}</template>
    <div role="none" class="px-3.5 pt-1.5 pb-2.5">
      <p class="m-0 text-base font-semibold">{{ name }}</p>
      <p class="m-0 font-mono text-xs text-text-3">{{ session.user.email }}</p>
    </div>
    <ApMenuItem :to="{ name: 'account' }">Your account</ApMenuItem>
    <template v-if="otherOrganizations.length > 1">
      <p role="none" class="ap-label px-3.5 pt-3 pb-1">Switch organization</p>
      <ApMenuItem
        v-for="org in otherOrganizations"
        :key="org.id"
        :to="{ name: 'org.home', params: { org: org.slug } }"
        >{{ org.name }}</ApMenuItem
      >
    </template>
    <!-- L21 (ux People.md Account): pending invitations open Account, where they're accepted. -->
    <ApMenuItem v-if="invitations > 0" :to="{ name: 'account' }" class="text-caution-text">{{
      invitations === 1 ? "1 invitation" : `${invitations} invitations`
    }}</ApMenuItem>
    <template v-if="eligible">
      <template v-if="admin.active.value">
        <ApMenuItem :to="{ name: 'admin' }">Admin area</ApMenuItem>
        <ApMenuItem @select="leaveAdmin">Leave admin mode</ApMenuItem>
      </template>
      <ApMenuItem v-else @select="enterAdmin">Enter admin mode</ApMenuItem>
    </template>
    <form role="none" method="post" action="/session" class="m-0 border-t border-hairline pt-1.5">
      <input type="hidden" name="_method" value="delete" />
      <input type="hidden" name="_csrf_token" :value="session.csrf_token" />
      <ApMenuItem type="submit">Sign out</ApMenuItem>
    </form>
  </ApMenuButton>
  <AdminModeSheet ref="adminSheet" />
</template>
