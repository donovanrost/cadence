<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { useNow } from "@/ui";
import { leaveAdminMode, useAdminMode } from "./admin-mode.ts";
import { useDisclosure } from "./disclosure.ts";

/**
 * L6 (Auth.md): while admin mode is on, a caution chip left of the UTC clock counting down to
 * the server's `expires_at`, with Admin area and Leave admin mode. Not a banner: that slot is U38's.
 */
const now = useNow();
const admin = useAdminMode(() => now.value);
const router = useRouter();
const root = ref<HTMLElement | null>(null);
const { open, toggle, close } = useDisclosure(root);
const itemClass =
  "flex h-10 w-full cursor-pointer items-center border-0 bg-transparent px-3.5 text-left text-base text-readout no-underline hover:bg-raised-hi";

async function leave() {
  close();
  await leaveAdminMode();
  // Leaving on an admin page returns home (Auth.md); elsewhere nothing moves.
  if (router.currentRoute.value.path.startsWith("/admin"))
    await router.push("/").catch((e: unknown) => console.error("Navigation failed", e));
}
</script>

<template>
  <div
    v-if="admin.active.value"
    ref="root"
    class="relative flex items-center border-l border-hairline"
  >
    <button
      type="button"
      class="h-full cursor-pointer border-0 bg-transparent px-3 font-mono text-xs font-semibold uppercase tabular"
      :class="admin.ending.value ? 'text-caution-text underline' : 'text-caution-text'"
      :aria-expanded="open"
      aria-haspopup="true"
      aria-controls="admin-mode-menu"
      @click="toggle"
    >
      Admin mode{{ admin.remaining.value ? ` · ${admin.remaining.value}` : "" }}
    </button>
    <div
      v-if="open"
      id="admin-mode-menu"
      class="absolute top-full right-0 z-30 min-w-[220px] border border-line bg-raised py-1.5"
    >
      <RouterLink :to="{ name: 'admin' }" :class="itemClass" @click="close">Admin area</RouterLink>
      <button type="button" :class="itemClass" @click="leave">Leave admin mode</button>
    </div>
  </div>
</template>
