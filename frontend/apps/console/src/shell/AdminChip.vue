<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { useNow } from "@/ui";
import { leaveAdminMode, useAdminMode } from "./admin-mode.ts";
import { useMenuButton } from "./menu-button.ts";

/**
 * L6 (Auth.md): while admin mode is on, a caution chip left of the UTC clock counting down to
 * the server's `expires_at`, with Admin area and Leave admin mode. Not a banner: that slot is U38's.
 */
const now = useNow();
const admin = useAdminMode(() => now.value);
const router = useRouter();
const root = ref<HTMLElement | null>(null);
const trigger = ref<HTMLButtonElement | null>(null);
const { open, toggle, close, onTriggerKey, onMenuKey } = useMenuButton(root);
/** A chosen item hands focus back to the trigger (design-language §6). */
function done() {
  close();
  trigger.value?.focus();
}
const itemClass =
  "flex h-10 w-full cursor-pointer items-center border-0 bg-transparent px-3.5 text-left text-base text-readout no-underline hover:bg-raised-hi focus:bg-raised-hi";

async function leave() {
  done();
  await leaveAdminMode();
  // Leaving on an admin page returns home (Auth.md); elsewhere nothing moves.
  if (router.currentRoute.value.path.startsWith("/admin"))
    await router
      .push({ name: "home" })
      .catch((e: unknown) => console.error("Navigation failed", e));
}
</script>

<template>
  <div
    v-if="admin.active.value"
    ref="root"
    class="relative flex items-center border-l border-hairline"
  >
    <button
      ref="trigger"
      type="button"
      class="h-full cursor-pointer border-0 bg-transparent px-3 font-mono text-xs font-semibold uppercase tabular"
      :class="admin.ending.value ? 'text-caution-text underline' : 'text-caution-text'"
      :aria-expanded="open"
      aria-haspopup="menu"
      aria-controls="admin-mode-menu"
      @click="toggle"
      @keydown="onTriggerKey"
    >
      Admin mode{{ admin.remaining.value ? ` · ${admin.remaining.value}` : "" }}
    </button>
    <div
      v-if="open"
      id="admin-mode-menu"
      role="menu"
      aria-label="Admin mode"
      class="absolute top-full right-0 z-30 min-w-[220px] border border-line bg-raised py-1.5"
      @keydown="onMenuKey"
    >
      <RouterLink
        :to="{ name: 'admin' }"
        :class="itemClass"
        role="menuitem"
        tabindex="-1"
        @click="done"
        >Admin area</RouterLink
      >
      <button type="button" :class="itemClass" role="menuitem" tabindex="-1" @click="leave">
        Leave admin mode
      </button>
    </div>
  </div>
</template>
