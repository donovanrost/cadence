<script setup lang="ts">
import { computed } from "vue";
import CockpitStatus from "../viewer/CockpitStatus.vue";

/**
 * Present's 24px status line (ux): `PLAYLIST · Ops wall · 2 of 5 · next in 0:18` (or `PAUSED`),
 * health, UTC and a visible Exit, in the takeover header slot like the viewer's kiosk line.
 */
const props = defineProps<{
  name: string;
  position: number;
  total: number;
  remainingMs: number;
  paused: boolean;
  skipped: number;
}>();
const emit = defineEmits<{ exit: [] }>();
const next = computed(() => {
  const s = Math.ceil(props.remainingMs / 1000);
  return `next in ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
});
/** Read on a step or a pause, not every second of the countdown (a11y B4). */
const spoken = computed(
  () => `${props.position} of ${props.total}${props.paused ? ", paused" : ""}`,
);
</script>

<template>
  <Teleport to="#ap-takeover-header" defer>
    <header class="flex h-6 items-center gap-3 border-b border-hairline bg-chrome px-3 text-xs">
      <h1 class="m-0 truncate font-display text-xs uppercase tracking-title text-readout">
        Playlist · {{ name }}
      </h1>
      <span class="font-mono text-text-3">
        {{ position }} of {{ total }} ·
        <span :class="paused ? 'text-caution-text' : ''">{{ paused ? "PAUSED" : next }}</span>
        <template v-if="skipped"> · {{ skipped }} archived skipped</template>
      </span>
      <span class="sr-only" aria-live="polite">{{ spoken }}</span>
      <span class="ml-auto flex items-center [&_div]:px-0 [&_div]:text-xs"><CockpitStatus /></span>
      <button
        type="button"
        class="cursor-pointer border-0 bg-transparent p-0 font-display text-xs uppercase tracking-btn text-text-3 hover:text-readout max-md:hit-44"
        @click="emit('exit')"
      >
        Exit
      </button>
    </header>
  </Teleport>
</template>
