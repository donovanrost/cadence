<script setup lang="ts">
import { computed } from "vue";
import { useRouter } from "vue-router";
import { ApMenuButton, ApMenuItem, useNow } from "@/ui";
import { leaveAdminMode, useAdminMode } from "./admin-mode.ts";

/**
 * L6 (Auth.md): while admin mode is on, a caution chip left of the UTC clock counting down to
 * the server's `expires_at`, with Admin area and Leave admin mode. Not a banner: that slot is U38's.
 * The kit menu button (design-language §6): a chosen item hands focus back to the chip first.
 */
const now = useNow();
const admin = useAdminMode(() => now.value);
const router = useRouter();
/** The chip's words are its name (the label matches what's on screen). */
const chipText = computed(
  () => `Admin mode${admin.remaining.value ? ` · ${admin.remaining.value}` : ""}`,
);
const chipClass = computed(
  () =>
    "h-full cursor-pointer border-0 bg-transparent px-3 font-mono text-xs font-semibold uppercase tabular text-caution-text" +
    (admin.ending.value ? " underline" : ""),
);

async function leave() {
  await leaveAdminMode();
  // Leaving on an admin page returns home (Auth.md); elsewhere nothing moves.
  if (router.currentRoute.value.path.startsWith("/admin"))
    await router
      .push({ name: "home" })
      .catch((e: unknown) => console.error("Navigation failed", e));
}
</script>

<template>
  <ApMenuButton
    v-if="admin.active.value"
    class="flex items-center border-l border-hairline"
    :label="chipText"
    menu-label="Admin mode"
    :trigger-class="chipClass"
    menu-class="min-w-[220px]"
  >
    <template #trigger>{{ chipText }}</template>
    <ApMenuItem :to="{ name: 'admin' }">Admin area</ApMenuItem>
    <ApMenuItem @select="leave">Leave admin mode</ApMenuItem>
  </ApMenuButton>
</template>
