<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from "vue";
import CockpitStatus from "../viewer/CockpitStatus.vue";

/**
 * Present's 24px status line (ux): `PLAYLIST · Ops wall · Power overview · 2 of 5 · next in 0:18`
 * (or `PAUSED`), health, UTC and a visible Exit, in the takeover header slot like the viewer's kiosk
 * line. Screen readers (ux Dashboards.md, Present): focus starts on the h1, and a polite region names
 * the dashboard, then its position, on each step and pause; never the countdown.
 */
const props = defineProps<{
  name: string;
  /** The dashboard on screen; "" until the playlist loads. */
  current: string;
  position: number;
  total: number;
  remainingMs: number;
  paused: boolean;
  /** The dashboard on screen couldn't load. */
  failed: boolean;
  skipped: number;
}>();
const emit = defineEmits<{ exit: [] }>();
const next = computed(() => {
  const s = Math.ceil(props.remainingMs / 1000);
  return `next in ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
});
/** Just resumed: 'Playing: …' until the next step. */
const resumed = ref(false);
watch(
  () => props.paused,
  (paused, was) => (resumed.value = was && !paused),
);
watch(
  () => props.position,
  () => (resumed.value = false),
);
const spoken = computed(() => {
  if (!props.total || !props.current) return "";
  const at = `${props.position} of ${props.total}`;
  if (props.failed) return `${props.current} couldn't load, ${at}`;
  if (props.paused) return `Paused: ${props.current}, ${at}`;
  return `${resumed.value ? "Playing: " : ""}${props.current}, ${at}`;
});
/**
 * The h1 sits in the takeover header, outside <main>, so the shell's route focus can't find it;
 * Present claims focus itself (ux 82d87ca69). The teleport is deferred: wait for it to land.
 */
const heading = ref<HTMLElement | null>(null);
onMounted(async () => {
  await nextTick();
  heading.value?.focus();
});
</script>

<template>
  <Teleport to="#ap-takeover-header" defer>
    <header class="flex h-6 items-center gap-3 border-b border-hairline bg-chrome px-3 text-xs">
      <h1
        ref="heading"
        tabindex="-1"
        class="m-0 truncate font-display text-xs uppercase tracking-title text-readout focus:outline-none"
      >
        Playlist · {{ name }}
      </h1>
      <span class="font-mono text-text-3">
        <template v-if="current">{{ current }} · </template>{{ position }} of {{ total }} ·
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
