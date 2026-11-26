<script setup lang="ts">
import { computed, ref } from "vue";
import { RouterLink } from "vue-router";
import { formatCount, formatDuration, useRowWindow, ApStatusMark } from "@/ui";
import { useCoarseNow } from "./coarseClock.ts";
import type { FleetSpacecraft } from "./api.ts";
import { fleetOpState, fleetStateWord } from "./matrix.ts";

/**
 * Fleet rows under 768px (ux pass 1 #3): two lines per spacecraft, no table, ids never wrap.
 * Line 1: name (the link, ≥44px tall) + state; line 2: SCID · plane · slot · last TLM in mono.
 *
 * Windowed like FleetTable (#868): only the rows in view plus overscan render, through the kit's
 * `useRowWindow`, with the skipped rows' height as the list's padding. Every item is ROW_HEIGHT
 * tall (both lines are nowrap). A focused row stays rendered, so Tab order and focus hold.
 */
const props = defineProps<{ rows: readonly FleetSpacecraft[]; total: number }>();
/** 1 border + 4 + 44 (name line) + 16 (meta line) + 6 + 4. */
const ROW_HEIGHT = 75;
/** Before the first measurement, only this many rows (a phone screen and some), never all. */
const FIRST_PAINT = 20;
const list = ref<HTMLElement | null>(null);
const win = useRowWindow(
  list,
  computed(() => props.rows.length),
  ref({ rowHeight: ROW_HEIGHT }),
  ref(null),
);
const shown = computed(() => {
  const w = win.value ?? {
    start: 0,
    end: Math.min(props.rows.length, FIRST_PAINT),
    before: 0,
    after: Math.max(0, props.rows.length - FIRST_PAINT) * ROW_HEIGHT,
  };
  return { ...w, rows: props.rows.slice(w.start, w.end) };
});
/** §2: Last TLM and Next contact move on the fleet's 10 s tick, not the 1 Hz clock. */
const now = useCoarseNow();
const pad = (n: number) => String(n).padStart(2, "0");
const meta = (sc: FleetSpacecraft) =>
  [
    `SCID ${sc.scid}`,
    sc.plane === null ? null : `P${pad(sc.plane)}${sc.slot === null ? "" : ` · ${pad(sc.slot)}`}`,
    sc.last_received_at
      ? formatDuration((now.value - Date.parse(sc.last_received_at)) / 1000)
      : "never heard",
  ]
    .filter((part): part is string => part !== null)
    .join(" · ");
const tint = (sc: FleetSpacecraft) =>
  sc.state === "critical"
    ? "text-crit-text"
    : sc.state === "caution"
      ? "text-caution-text"
      : sc.state === "stale"
        ? "text-stale-text"
        : "text-text-2";
</script>

<template>
  <div>
    <ul
      ref="list"
      class="m-0 list-none px-0"
      aria-label="Fleet"
      :style="{ paddingTop: `${shown.before}px`, paddingBottom: `${shown.after}px` }"
    >
      <li
        v-for="(sc, i) in shown.rows"
        :key="sc.id"
        :data-row-index="shown.start + i"
        :aria-posinset="shown.start + i + 1"
        :aria-setsize="rows.length"
        class="overflow-hidden border-hairline px-4 py-1"
        :class="shown.start + i === 0 ? '' : 'border-t'"
        :style="{ height: `${ROW_HEIGHT}px` }"
      >
        <div class="flex min-h-11 items-center justify-between gap-3">
          <RouterLink
            :to="{ name: 'ops.spacecraft', params: { scId: sc.scid } }"
            class="inline-flex min-h-11 items-center font-semibold whitespace-nowrap text-readout no-underline"
            >{{ sc.name }}</RouterLink
          >
          <span class="inline-flex items-center gap-2 text-md whitespace-nowrap" :class="tint(sc)">
            <ApStatusMark :state="fleetOpState(sc.state)" />{{ fleetStateWord(sc.state) }}
          </span>
        </div>
        <p class="m-0 pb-1.5 font-mono text-xs leading-4 whitespace-nowrap text-text-3">
          {{ meta(sc) }}
        </p>
      </li>
    </ul>
    <p class="m-0 border-t border-hairline px-4 py-2.5 font-mono text-xs text-text-4 uppercase">
      {{ formatCount(rows.length) }} of {{ formatCount(total) }}
    </p>
  </div>
</template>
