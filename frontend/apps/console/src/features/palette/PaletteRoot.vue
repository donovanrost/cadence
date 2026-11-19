<script setup lang="ts">
import { linkByName, type ParamlessRouteName } from "@/shell";
import { onScopeDispose, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { registerPalette, useConsoleScope, usePalette, useSmallScreen } from "@/shell/index.ts";
import MobileSearch from "./MobileSearch.vue";
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
const route = useRoute();
const small = useSmallScreen();
// Any navigation closes it (a row opening, or Back on a phone, Mobile.md › Search).
watch(
  () => route.fullPath,
  () => palette.hide(),
);

const typing = (target: EventTarget | null) =>
  target instanceof HTMLElement &&
  (target.isContentEditable || ["INPUT", "SELECT", "TEXTAREA"].includes(target.tagName));
// keyed-by-text: the second key of a G-chord, as KeyboardEvent.key gives it (lower-cased)
const CHORDS: Readonly<Record<string, ParamlessRouteName>> = { n: "ops.now", c: "ops.contacts" };
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
  router
    .push(linkByName(name))
    .catch((error: unknown) => console.error("Navigation failed", error));
}
window.addEventListener("keydown", onKey);
onScopeDispose(() => window.removeEventListener("keydown", onKey));
</script>

<template>
  <template v-if="palette.open.value">
    <!-- Phones in a mission get the on-call search sheet (Mobile.md › Search); else the query line. -->
    <MobileSearch v-if="small && scope.kind === 'mission'" @close="palette.hide" />
    <PaletteDialog v-else @close="palette.hide" />
  </template>
</template>
