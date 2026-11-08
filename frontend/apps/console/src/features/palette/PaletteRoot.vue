<script setup lang="ts">
import { onScopeDispose } from "vue";
import { useRouter } from "vue-router";
import { registerPalette, useConsoleScope, usePalette } from "@/shell/index.ts";
import PaletteDialog from "./PaletteDialog.vue";

/**
 * ⌘K query line (Palette.md), mounted once in App.vue. Registering it reveals the top-bar
 * trigger and the ⌘K / `/` shortcuts. Also owns the `G N` / `G C` page chords (palette closed,
 * not typing).
 */
registerPalette();
const palette = usePalette();
const scope = useConsoleScope();
const router = useRouter();

const typing = (target: EventTarget | null) =>
  target instanceof HTMLElement &&
  (target.isContentEditable || ["INPUT", "SELECT", "TEXTAREA"].includes(target.tagName));
const CHORDS: Readonly<Record<string, string>> = { n: "ops.now", c: "ops.contacts" };
let armedUntil = 0;

function onKey(event: KeyboardEvent) {
  if (palette.open.value || event.metaKey || event.ctrlKey || event.altKey || typing(event.target))
    return;
  if (scope.value.kind !== "mission") return;
  const key = event.key.toLowerCase();
  if (key === "g") {
    armedUntil = Date.now() + 1000;
    return;
  }
  const name = Date.now() < armedUntil ? CHORDS[key] : undefined;
  armedUntil = 0;
  if (!name) return;
  event.preventDefault();
  router.push({ name }).catch((error: unknown) => console.error("Navigation failed", error));
}
window.addEventListener("keydown", onKey);
onScopeDispose(() => window.removeEventListener("keydown", onKey));
</script>

<template>
  <PaletteDialog v-if="palette.open.value" @close="palette.hide" />
</template>
