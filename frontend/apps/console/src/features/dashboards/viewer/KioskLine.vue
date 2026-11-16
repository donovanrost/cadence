<script setup lang="ts">
import { onBeforeUnmount, onMounted } from "vue";
import CockpitStatus from "./CockpitStatus.vue";
import { inDialog } from "../focus-fallback.ts";

/**
 * Kiosk (ux): the takeover header collapses to a 24px status line (title · range · health ·
 * UTC). It takes the same shell slot as TakeoverHeader (lead), as the page's header landmark,
 * with a visible Exit for pointer and touch; Esc also leaves.
 */
defineProps<{ title: string; range: string }>();
const emit = defineEmits<{ exit: [] }>();
function onKey(event: KeyboardEvent) {
  // Esc in a sheet opened here (Inspect) closes only the sheet.
  if (event.key === "Escape" && !inDialog(event)) emit("exit");
}
onMounted(() => window.addEventListener("keydown", onKey));
onBeforeUnmount(() => window.removeEventListener("keydown", onKey));
</script>

<template>
  <Teleport to="#ap-takeover-header" defer>
    <header class="flex h-6 items-center gap-3 border-b border-hairline bg-chrome px-3 text-xs">
      <h1 class="m-0 truncate font-display text-xs uppercase tracking-title text-readout">
        {{ title }}
      </h1>
      <span class="font-mono text-text-3">{{ range }}</span>
      <span class="ml-auto flex items-center [&_div]:px-0 [&_div]:text-xs"><CockpitStatus /></span>
      <button
        type="button"
        class="cursor-pointer border-0 bg-transparent p-0 font-display text-xs uppercase tracking-btn text-text-3 hover:text-readout max-md:hit-44"
        @click="emit('exit')"
      >
        Exit kiosk
      </button>
    </header>
  </Teleport>
</template>
