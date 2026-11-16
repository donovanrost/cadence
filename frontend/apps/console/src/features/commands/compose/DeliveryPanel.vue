<script setup lang="ts">
import { computed } from "vue";
import {
  formatCountdown,
  formatHourMinute,
  useNow,
  ApEmptyState,
  ApPanel,
  ApStatusMark,
} from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import type { NextContact, TargetEndpoints } from "../groups/api.ts";
import { useMissionScope } from "@/shell/index.ts";
import { useStationCodes } from "@/features/contacts/useStationCodes.ts";
import EndpointCell from "./EndpointCell.vue";

/**
 * C4 · Delivery plan: each target's own next booked contact. The preflight's contact check
 * (confirmed/active bookings, with the station) is authoritative once it answers; until then the
 * fleet's next AOS. Targets without one get a caution row. Umbra margin omitted (DECISIONS #4).
 */
const props = defineProps<{
  targets: readonly FleetSpacecraft[];
  contacts: ReadonlyMap<string, NextContact | null> | null;
  /** Per target: what routing resolves (DECISIONS #41), with the endpoints to override with. */
  endpoints: ReadonlyMap<string, TargetEndpoints>;
  overrides: Readonly<Record<string, string>>;
  /** U68: the request's expiry (epoch ms); a target whose next AOS is after it gets a caution. */
  expiresAt?: number | null | undefined;
}>();
defineEmits<{ override: [spacecraftId: string, endpointId: string | null] }>();
const now = useNow();
const LIMIT = 40;
type Row = { sc: FleetSpacecraft; aos: string | null; station: string | null; ref: string | null };
const scope = useMissionScope();
const stations = useStationCodes(computed(() => scope.value.mission.id));
/** "SVB-1 · Northlight": the contact's station and its provider from the stations index. */
const via = (r: Row) => {
  if (!r.station) return null;
  // r.ref is the provider's station ref, r.station its code: both text lookups.
  const provider = stations.byRef(r.ref)?.provider ?? stations.byRef(r.station)?.provider;
  return provider ? `${r.station} · ${provider}` : r.station;
};
const all = computed<Row[]>(() =>
  props.targets.map((sc) => {
    const c = props.contacts?.get(sc.id);
    return c === undefined
      ? { sc, aos: sc.next_aos_at, station: null, ref: null }
      : {
          sc,
          aos: c?.aos ?? null,
          station: c?.station_code ?? null,
          ref: c?.ground_station_ref ?? null,
        };
  }),
);
/** 'Expires before its next contact (AOS 04:12Z).' when the expiry comes first; arming isn't blocked. */
const expiresFirst = (r: Row) =>
  r.aos && props.expiresAt != null && props.expiresAt < Date.parse(r.aos)
    ? `Expires before its next contact (AOS ${formatHourMinute(new Date(r.aos))}).`
    : null;
const rows = computed(() =>
  [...all.value]
    .sort((a, b) => (a.aos ? Date.parse(a.aos) : Infinity) - (b.aos ? Date.parse(b.aos) : Infinity))
    .slice(0, LIMIT),
);
const noContact = computed(() => all.value.filter((r) => r.aos === null).length);
</script>

<template>
  <ApPanel index="C4" title="Delivery plan" meta="each target at its own next AOS" flush>
    <ApEmptyState v-if="targets.length === 0" headline="No targets yet" />
    <ul v-else class="m-0 list-none p-0">
      <li
        v-for="row in rows"
        :key="row.sc.id"
        class="flex items-center gap-3 border-t border-hairline-faint px-4 py-1.5 first:border-t-0"
      >
        <ApStatusMark :state="row.aos && !expiresFirst(row) ? 'live' : 'caution'" />
        <span class="w-32 font-mono text-md text-readout">{{ row.sc.name }}</span>
        <span class="font-mono text-sm" :class="row.aos ? 'text-text-2' : 'text-caution-text'">
          {{ row.aos ? `AOS ${formatCountdown(new Date(row.aos), now)}` : "No booked contact" }}
        </span>
        <span v-if="expiresFirst(row)" class="text-sm text-caution-text">{{
          expiresFirst(row)
        }}</span>
        <EndpointCell
          class="ml-auto"
          :name="row.sc.name"
          :info="endpoints.get(row.sc.id)"
          :override="overrides[row.sc.id]"
          :via="via(row)"
          @change="(id) => $emit('override', row.sc.id, id)"
        />
      </li>
      <li
        v-if="targets.length > LIMIT"
        class="border-t border-hairline-faint px-4 py-1.5 font-mono text-xs text-text-4 uppercase"
      >
        and {{ targets.length - LIMIT }} more
      </li>
    </ul>
    <p v-if="noContact" class="m-0 border-t border-hairline px-4 py-2 text-md text-caution-text">
      {{ noContact }} without a booked contact:
      {{ noContact === 1 ? "its uplink waits" : "their uplinks wait" }} until one is booked.
      <RouterLink :to="{ name: 'ops.contacts' }" class="text-readout">Open contacts</RouterLink>
    </p>
  </ApPanel>
</template>
