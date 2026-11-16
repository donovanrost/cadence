<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue";
import { RouterLink } from "vue-router";
import { useFleet } from "../useFleet.ts";
import { useConnection } from "@/live";
import { useMissionScope } from "@/shell";
import { ApStatusMark, formatHourMinute, stateTextClass } from "@/ui";
import { POSTURE_FRESHNESS_GAP_MS, postureChips } from "./posture.ts";

/**
 * The top bar's fleet posture (ux information-architecture.md §Top bar, ca31e877a). It replaces
 * the legacy context rail and is the dashboard cockpit's chips without their clock (the top bar's
 * clocks carry UTC).
 * - Shown in both modes at mission scope; nothing until the fleet has loaded.
 * - Below 768 it isn't shown (the tab bar's Alarms count and Now cover it).
 * - From 768 to 1279 it shows marks and counts; the words stay in each link's name and title.
 * - When the live link drops, the counts stay, stale-tinted, with 'as of HH:MMZ'.
 * - Changes aren't announced; a new crit flashes its chip once (no flash with reduced motion).
 */
const scope = useMissionScope();
// live: false: the fleet push is per screen, so this cluster refetches on the mission's hints.
// It's on every screen and the read is ~300 KB, so telemetry hints refresh it at most once a
// minute; the stale count may lag up to 60 s (lead). State hints still refetch within 2 s.
// When api's counts-only posture read lands, read that instead.
const fleet = useFleet(
  computed(() => scope.value.mission.id),
  { live: false, freshnessGapMs: POSTURE_FRESHNESS_GAP_MS },
);
const connection = useConnection();
const ready = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value : null,
);
const chips = computed(() => (ready.value ? postureChips(ready.value) : []));
const offline = computed(() => connection.value === "offline");
const asOf = computed(() =>
  ready.value ? formatHourMinute(new Date(ready.value.observed_at)) : "",
);

const flashing = ref(false);
let timer: ReturnType<typeof setTimeout> | null = null;
watch(
  () => ready.value?.counts.critical ?? null,
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
