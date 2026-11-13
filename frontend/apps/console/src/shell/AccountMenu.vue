<script setup lang="ts">
import { computed, ref } from "vue";
import { initials, useNow } from "@/ui";
import AdminModeSheet from "./AdminModeSheet.vue";
import { leaveAdminMode, useAdminMode } from "./admin-mode.ts";
import { useDisclosure } from "./disclosure.ts";
import { hasCapability, useSession } from "./session.ts";

const session = useSession();
const root = ref<HTMLElement | null>(null);
const { open, toggle, close } = useDisclosure(root);

const name = computed(() => session.user.display_name ?? session.user.email);
const otherOrganizations = computed(() =>
  session.organizations.filter((org) => org.missions.length > 0),
);
/** L6: eligible admins step up from here; while on, the menu offers the area and Leave. */
const eligible = computed(
  () => session.platform_admin_eligible || hasCapability(session, "platform_admin"),
);
const now = useNow();
const admin = useAdminMode(() => now.value);
const adminSheet = ref<InstanceType<typeof AdminModeSheet> | null>(null);
function enterAdmin() {
  close();
  adminSheet.value?.open();
}
function leaveAdmin() {
  close();
  void leaveAdminMode();
}
const itemClass =
  "flex h-10 w-full items-center px-3.5 text-base text-readout no-underline hover:bg-raised-hi";
</script>

<template>
  <div ref="root" class="relative ml-auto flex border-l border-hairline">
    <button
      type="button"
      class="w-[52px] cursor-pointer border-0 bg-transparent font-display text-base font-semibold tracking-[.1em] text-readout hover:bg-raised"
      :aria-label="`${initials(name)}, account menu for ${name}`"
      :aria-expanded="open"
      aria-haspopup="true"
      aria-controls="account-menu"
      @click="toggle"
    >
      {{ initials(name) }}
    </button>
    <div
      id="account-menu"
      v-if="open"
      class="absolute top-full right-0 z-30 min-w-[260px] border border-line bg-raised py-1.5"
    >
      <div class="px-3.5 pt-1.5 pb-2.5">
        <p class="m-0 text-base font-semibold">{{ name }}</p>
        <p class="m-0 font-mono text-xs text-text-3">{{ session.user.email }}</p>
      </div>
      <RouterLink :to="{ name: 'account' }" :class="itemClass" @click="close"
        >Your account</RouterLink
      >
      <template v-if="otherOrganizations.length > 1">
        <p class="ap-label px-3.5 pt-3 pb-1">Switch organization</p>
        <RouterLink
          v-for="org in otherOrganizations"
          :key="org.id"
          :to="{ name: 'org.home', params: { org: org.slug } }"
          :class="itemClass"
          @click="close"
          >{{ org.name }}</RouterLink
        >
      </template>
      <template v-if="eligible">
        <template v-if="admin.active.value">
          <!-- The console admin area is §11 L7; until it ships, the existing one. -->
          <a href="/admin" :class="itemClass">Admin area ↗</a>
          <button
            type="button"
            :class="[itemClass, 'cursor-pointer border-0 bg-transparent text-left']"
            @click="leaveAdmin"
          >
            Leave admin mode
          </button>
        </template>
        <button
          v-else
          type="button"
          :class="[itemClass, 'cursor-pointer border-0 bg-transparent text-left']"
          @click="enterAdmin"
        >
          Enter admin mode
        </button>
      </template>
      <form method="post" action="/session" class="m-0 border-t border-hairline pt-1.5">
        <input type="hidden" name="_method" value="delete" />
        <input type="hidden" name="_csrf_token" :value="session.csrf_token" />
        <button
          type="submit"
          :class="[itemClass, 'cursor-pointer border-0 bg-transparent text-left']"
        >
          Sign out
        </button>
      </form>
    </div>
  </div>
  <AdminModeSheet ref="adminSheet" />
</template>
