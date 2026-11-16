<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue";
import { RouterLink } from "vue-router";
import { useConnection } from "@/live";
import { useFleetPosture } from "@/shell";
import { ApStatusMark, formatHourMinute, stateTextClass } from "@/ui";
import { postureChips } from "./posture.ts";

/**
 * The top bar's fleet posture (ux information-architecture.md §Top bar, ca31e877a). It replaces
 * the legacy context rail and is the dashboard cockpit's chips without their clock (the top bar's
 * clocks carry UTC).
 * - Shown in both modes at mission scope; nothing until /counts has its posture (U20).
 * - Telemetry degraded: stale and never heard merge into '▨ n not heard recently' (ux fb5e5ded0).
 * - Below 768 it isn't shown (the tab bar's Alarms count and Now cover it).
 * - From 768 to 1279 it shows marks and counts; the words stay in each link's name and title.
 * - When the live link drops, the counts stay, stale-tinted, with 'as of HH:MMZ'.
 * - Changes aren't announced; a new crit flashes its chip once (no flash with reduced motion).
 */
// The shell's one /counts read carries the posture (api-ops 64b16a90e): a few hundred bytes,
// refetched on the mission's hints (telemetry at most every 10 s), not the ~300 KB fleet read.
const posture = useFleetPosture();
const connection = useConnection();
const ready = computed(() => posture.value ?? null);
const chips = computed(() => {
  const p = ready.value;
  if (!p) return [];
  return postureChips({
    counts: p,
    limits: { configured: p.limits_configured },
    telemetry: p.telemetry,
  });
});
const offline = computed(() => connection.value === "offline");
const asOf = computed(() =>
  ready.value ? formatHourMinute(new Date(ready.value.observed_at)) : "",
);

const flashing = ref(false);
let timer: ReturnType<typeof setTimeout> | null = null;
watch(
  () => ready.value?.critical ?? null,
  (now, before) => {
    if (now === null || before === null || before === undefined || now <= before) return;
    flashing.value = true;
    if (timer !== null) clearTimeout(timer);
    timer = setTimeout(() => (flashing.value = false), 2_000);
  },
);
onBeforeUnmount(() => {
  if (timer !== null) clearTimeout(timer);
});
</script>

<template>
  <div
    v-if="chips.length"
    data-fleet-posture
    class="flex items-center gap-2 border-l border-hairline px-4 font-mono text-md max-md:hidden"
  >
    <template v-for="(chip, i) in chips" :key="chip.key">
      <span v-if="i > 0" aria-hidden="true" class="text-text-4">·</span>
      <RouterLink
        :to="chip.to"
        :aria-label="chip.label"
        :title="chip.label"
        class="flex items-center gap-1.5 tabular-nums no-underline hover:underline"
        :class="[
          stateTextClass(offline ? 'stale' : chip.state),
          chip.key === 'crit' && flashing ? 'motion-safe:animate-pulse' : '',
        ]"
      >
        <ApStatusMark :state="chip.state" />
        <template v-if="chip.count !== null"
          >{{ chip.count }}<span class="max-xl:hidden">{{ chip.word }}</span></template
        >
        <template v-else>{{ chip.word }}</template>
      </RouterLink>
    </template>
    <span v-if="offline" class="text-stale-text">as of {{ asOf }}</span>
  </div>
</template>
