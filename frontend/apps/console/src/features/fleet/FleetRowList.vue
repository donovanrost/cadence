<script setup lang="ts">
import { RouterLink } from "vue-router";
import { formatCount, formatDuration, ApStatusMark } from "@/ui";
import { useCoarseNow } from "./coarseClock.ts";
import type { FleetSpacecraft } from "./api.ts";
import { fleetOpState, fleetStateWord } from "./matrix.ts";

/**
 * Fleet rows under 768px (ux pass 1 #3): two lines per spacecraft, no table, ids never wrap.
 * Line 1: name (the link, ≥44px tall) + state; line 2: SCID · plane · slot · last TLM in mono.
 */
defineProps<{ rows: readonly FleetSpacecraft[]; total: number }>();
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
    <ul class="m-0 list-none p-0" aria-label="Fleet">
      <li
        v-for="sc in rows"
        :key="sc.id"
        class="border-t border-hairline px-4 py-1 first:border-t-0"
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
        <p class="m-0 pb-1.5 font-mono text-xs whitespace-nowrap text-text-3">{{ meta(sc) }}</p>
      </li>
    </ul>
    <p class="m-0 border-t border-hairline px-4 py-2.5 font-mono text-xs text-text-4 uppercase">
      {{ formatCount(rows.length) }} of {{ formatCount(total) }}
    </p>
  </div>
</template>
