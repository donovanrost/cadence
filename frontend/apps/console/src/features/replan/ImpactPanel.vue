<script setup lang="ts">
import type { RemoteState } from "@/api";
import type { Passes } from "@/features/contacts/index.ts";
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
import type { Impact } from "./impact.ts";

/** A Impact (v1): the live plan's rejected / failed / canceled bookings (DECISIONS #25). */
defineProps<{
  live: PlanDetail;
  state: RemoteState<Passes>;
  impact: Impact | null;
  hasWindow: boolean;
}>();
defineEmits<{ retry: [] }>();
</script>

<template>
  <ApPanel
    index="A"
    title="Impact"
    :meta="impact ? `${plural(impact.passes, 'booking')} lost` : undefined"
    pane
    flush
  >
    <ApEmptyState v-if="!hasWindow" headline="The live plan has no passes" />
    <ApRemote v-else :state="state" loading-label="Loading bookings…" @retry="$emit('retry')">
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
            :sentence="
              live.chain_head && live.chain_head !== live.id
                ? 'Every booking is holding, including the repair\'s.'
                : 'Every booking of the live plan is holding.'
            "
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
            v-if="impact.rows.length > 40"
            class="m-0 border-t border-hairline px-4 py-2 text-sm text-text-3"
          >
            Showing 40 of {{ impact.passes }}.
          </p>
        </template>
      </template>
    </ApRemote>
  </ApPanel>
</template>
