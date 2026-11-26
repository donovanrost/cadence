<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { ApEmptyState, ApPanel, ApRemote, ApStatTile, ApTag, formatShort, useNow } from "@/ui";
import {
  fetchStationImpact,
  outageWindow,
  sourceText,
  stationTag,
  type StationAvailability,
} from "./station.ts";

/** A Impact (station entry, S7): station state, the provider's report, passes hit in the outage. */
const props = defineProps<{
  missionId: MissionId;
  stationId: string;
  stationName: string;
  availability: StationAvailability;
}>();
const now = useNow();
const win = computed(() => outageWindow(props.availability, now.value));
const impactKey = computed(() => {
  const w = win.value;
  if (!w) return null;
  const to = w.to ?? w.eta ?? new Date(Date.parse(w.from) + 86_400_000).toISOString();
  return { missionId: props.missionId, stationId: props.stationId, from: w.from, to };
});
const impact = useRemoteQuery(impactKey, fetchStationImpact);
</script>

<template>
  <ApPanel index="A" title="Impact" pane flush>
    <div class="flex flex-col gap-2 border-b border-hairline px-4 py-3">
      <div class="flex items-center justify-between gap-2">
        <span class="text-base font-semibold text-readout">{{ stationName }}</span>
        <ApTag v-bind="stationTag(availability.status.state, win !== null)" />
      </div>
      <p v-if="availability.status.state === 'up'" class="m-0 text-sm text-text-3">
        {{
          win
            ? `Nothing reports it down right now; ${win.kind === "maintenance" ? "maintenance" : "an outage"} is reported from ${formatShort(new Date(win.from))}.`
            : "Nothing reports this station down right now."
        }}
        That isn't live telemetry.
      </p>
      <p v-if="win" class="m-0 text-sm text-text-3">
        {{ win.kind === "maintenance" ? "Maintenance" : "Outage" }} from
        {{ formatShort(new Date(win.from))
        }}<template v-if="win.to"> to {{ formatShort(new Date(win.to)) }}</template
        ><template v-else-if="win.eta"
          >, expected back {{ formatShort(new Date(win.eta)) }}</template
        ><template v-else>, no end reported</template>. {{ sourceText(win)
        }}<template v-if="win.reason">: {{ win.reason }}</template
        >.
      </p>
    </div>
    <ApEmptyState
      v-if="!win"
      headline="No outage to re-plan around"
      sentence="Nothing reports this station down or in maintenance now or in the next 7 days."
    />
    <ApRemote
      v-else
      :state="impact.state.value"
      loading-label="Finding passes hit…"
      @retry="impact.refetch"
    >
      <template #default="{ value }">
        <div class="grid grid-cols-3 gap-px bg-hairline">
          <ApStatTile
            label="Passes hit"
            :value="value.passes_hit"
            :state="value.passes_hit > 0 ? 'crit' : 'neutral'"
            caption="still booked"
          />
          <ApStatTile
            label="Already lost"
            :value="value.lost.count"
            :state="value.lost.count > 0 ? 'caution' : 'neutral'"
            caption="canceled, rejected or failed"
          />
          <ApStatTile label="Spacecraft" :value="value.spacecraft_count" />
        </div>
        <p class="m-0 border-t border-hairline px-4 py-2 text-sm text-text-3">
          Bookings that never named a station can't be attributed and aren't counted.<template
            v-if="value.truncated"
          >
            The list was truncated by the server.</template
          >
        </p>
      </template>
    </ApRemote>
  </ApPanel>
</template>
