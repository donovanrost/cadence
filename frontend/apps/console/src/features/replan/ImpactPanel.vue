<script setup lang="ts">
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { fetchPasses } from "@/features/contacts/index.ts";
import type { PlanDetail } from "@/features/scheduling/index.ts";
import {
  ApEmptyState,
  ApPanel,
  ApRemote,
  ApStatTile,
  ApStatusMark,
  formatShort,
  plural,
} from "@/ui";
import { impactOf } from "./impact.ts";

/** A Impact (v1): the live plan's rejected / failed / canceled bookings (DECISIONS #25). */
const props = defineProps<{ missionId: string; live: PlanDetail }>();
const key = computed(() => {
  const w = props.live.window;
  return w.from && w.to
    ? { missionId: props.missionId, from: new Date(w.from), to: new Date(w.to) }
    : null;
});
const passes = useRemoteQuery(key, (k, signal) =>
  fetchPasses(k.missionId, { from: k.from, to: k.to }, signal),
);
const impact = computed(() =>
  passes.state.value.status === "ready"
    ? impactOf(passes.state.value.value.passes, props.live.id, passes.state.value.value.truncated)
    : null,
);
</script>

<template>
  <ApPanel
    index="A"
    title="Impact"
    :meta="impact ? plural(impact.passes, 'booking', 'bookings') + ' lost' : undefined"
    pane
    flush
  >
    <ApEmptyState v-if="!key" headline="The live plan has no passes" />
    <ApRemote
      v-else
      :state="passes.state.value"
      loading-label="Loading bookings…"
      @retry="passes.refetch"
    >
      <template #default>
        <template v-if="impact">
          <div class="grid grid-cols-3 gap-px border-b border-hairline bg-hairline">
            <ApStatTile
              label="Passes hit"
              :value="impact.passes"
              :state="impact.passes > 0 ? 'caution' : 'neutral'"
            />
            <ApStatTile label="Spacecraft" :value="impact.spacecraft" />
            <ApStatTile
              label="Stations"
              :value="impact.stations.length"
              :caption="impact.stations.join(', ') || undefined"
            />
          </div>
          <ApEmptyState
            v-if="impact.passes === 0"
            state="off"
            :headline="`No lost bookings on r${live.version}`"
            sentence="Every booking of the live plan is holding."
          />
          <ul v-else class="m-0 list-none p-0">
            <li
              v-for="row in impact.rows.slice(0, 40)"
              :key="row.id"
              class="grid grid-cols-[12px_minmax(0,1fr)] gap-2 border-t border-hairline px-4 py-2 first:border-t-0"
            >
              <span class="pt-1.5"><ApStatusMark state="caution" /></span>
              <span class="flex flex-col">
                <span class="text-md text-readout"
                  >{{ row.spacecraft }} · <span class="font-mono">{{ row.station }}</span> ·
                  <time class="font-mono text-sm text-text-3" :datetime="row.startsAt">{{
                    formatShort(new Date(row.startsAt))
                  }}</time></span
                >
                <span class="text-sm text-text-3">{{ row.why }}</span>
              </span>
            </li>
          </ul>
          <p
            v-if="impact.truncated || impact.rows.length > 40"
            class="m-0 border-t border-hairline px-4 py-2 text-sm text-text-3"
          >
            Showing {{ Math.min(40, impact.rows.length) }} of {{ impact.passes
            }}{{ impact.truncated ? "; the window was truncated by the server" : "" }}.
          </p>
          <p class="m-0 border-t border-hairline px-4 py-2 text-sm text-text-3">
            Station status isn't reported yet; this lists the bookings providers rejected, failed or
            canceled.
          </p>
        </template>
      </template>
    </ApRemote>
  </ApPanel>
</template>
