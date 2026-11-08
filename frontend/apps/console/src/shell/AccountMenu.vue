<script setup lang="ts">
import { computed, ref } from "vue";
import { initials } from "@/ui";
import { useDisclosure } from "./disclosure.ts";
import { hasCapability, useSession } from "./session.ts";

const session = useSession();
const root = ref<HTMLElement | null>(null);
const { open, toggle, close } = useDisclosure(root);

const name = computed(() => session.user.display_name ?? session.user.email);
const otherOrganizations = computed(() =>
  session.organizations.filter((org) => org.missions.length > 0),
);
const platformAdmin = computed(() => hasCapability(session, "platform_admin"));
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
      <RouterLink :to="{ name: 'notifications' }" :class="itemClass" @click="close"
        >Notifications</RouterLink
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
      <a v-if="platformAdmin" href="/admin" :class="itemClass">Platform admin ↗</a>
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
</template>
