<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { RouterLink } from "vue-router";
import { useFleet } from "../useFleet.ts";
import { useConnection } from "@/live";
import { useMissionScope } from "@/shell";
import { ApStatusMark, formatHourMinute, stateTextClass } from "@/ui";
import {
  POSTURE_FRESHNESS_GAP_MS,
  POSTURE_WIDE_QUERY,
  postureChips,
  postureCompact,
} from "./posture.ts";

/**
 * The top bar's fleet posture (ux information-architecture.md §Top bar, ca31e877a). It replaces
 * the legacy context rail and is the dashboard cockpit's chips without their clock (the top bar's
 * clocks carry UTC).
 * - Shown in both modes at mission scope; nothing until the fleet has loaded.
 * - Below 768 it isn't shown (the tab bar's Alarms count and Now cover it).
 * - Words from 1600; below that, and whenever the never-wrapping top bar is tight, it's compact:
 *   marks and counts, short words for count-less chips, with the full words in each link's name and
 *   title (ux d39a9c150, 9c49c76ab). A hidden copy measures the full width so the cluster knows
 *   when words fit again.
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
const root = ref<HTMLElement | null>(null);
const measure = ref<HTMLElement | null>(null);
const media =
  typeof window.matchMedia === "function" ? window.matchMedia(POSTURE_WIDE_QUERY) : null;
const wide = ref(media?.matches ?? true);
const compact = ref(!wide.value);
const onMedia = (e: MediaQueryListEvent) => (wide.value = e.matches);
/** The top bar's shrinking item (`data-topbar-flex="<min px>"`): its width above that minimum. */
function fit() {
  const header = root.value?.closest("header");
  if (!header || !root.value || !measure.value) return void (compact.value = !wide.value);
  const flex = header.querySelector<HTMLElement>("[data-topbar-flex]");
  const room = flex
    ? flex.getBoundingClientRect().width - Number(flex.dataset.topbarFlex ?? 0)
    : header.clientWidth - header.scrollWidth;
  compact.value = postureCompact({
    wide: wide.value,
    compact: compact.value,
    overflow: header.scrollWidth > header.clientWidth + 1,
    room,
    grow: measure.value.getBoundingClientRect().width - root.value.getBoundingClientRect().width,
  });
}
let observer: ResizeObserver | null = null;
onMounted(() => {
  media?.addEventListener("change", onMedia);
  if (typeof ResizeObserver === "undefined") return;
  observer = new ResizeObserver(() => fit());
  const header = root.value?.closest("header");
  if (header) observer.observe(header);
});
watch([wide, chips, root], async () => {
  await nextTick();
  if (root.value && measure.value) observer?.observe(measure.value);
  fit();
});
onBeforeUnmount(() => {
  if (timer !== null) clearTimeout(timer);
  media?.removeEventListener("change", onMedia);
  observer?.disconnect();
});
</script>

<template>
  <div
    v-if="chips.length"
    ref="root"
    data-fleet-posture
    :data-compact="compact ? 'true' : undefined"
    class="relative flex items-center gap-2 border-l border-hairline px-4 font-mono text-md whitespace-nowrap max-md:hidden"
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
          >{{ chip.count }}<span v-if="!compact">{{ chip.word }}</span></template
        >
        <template v-else>{{ compact ? chip.short : chip.word }}</template>
      </RouterLink>
    </template>
    <span v-if="offline" class="text-stale-text">as of {{ asOf }}</span>
    <!-- The words' width, measured off-screen (right-anchored, invisible, never focusable). -->
    <span
      ref="measure"
      aria-hidden="true"
      class="pointer-events-none invisible absolute top-0 right-0 flex items-center gap-2 px-4"
    >
      <template v-for="(chip, i) in chips" :key="chip.key">
        <span v-if="i > 0">·</span>
        <span class="flex items-center gap-1.5"
          ><ApStatusMark :state="chip.state" />{{ chip.count ?? ""
          }}<span>{{ chip.word }}</span></span
        >
      </template>
      <span v-if="offline">as of {{ asOf }}</span>
    </span>
  </div>
</template>
