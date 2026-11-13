<script setup lang="ts">
import { computed, ref } from "vue";
import { describeApiError, isError } from "@/api/index.ts";
import {
  formatDuration,
  useNow,
  ApButton,
  ApCallout,
  ApSegmented,
  ApSelect,
  ApSheet,
  ApTag,
  ApTextarea,
  ApTimeRange,
  type RangePreset,
  type TimeRange,
} from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import type { GroundStation, Pass } from "./api.ts";
import {
  confirmLine,
  emptyWords,
  expiryWords,
  offerBlocked,
  outcomeWords,
  providerWords,
  reserveOffer,
  searchOffers,
  stationWords,
  windowWords,
  type Offer,
  type Reserve,
  type Search,
} from "./singleBookings.ts";

/**
 * Book a pass (ux Contacts.md, §11 L15): search the spacecraft's ready routes, pick an offer before
 * its token expires, book it outside a plan. Reserving is idempotent, so "unclear" offers Try again.
 * `booked` hands the new pass to Contacts so D3 shows the bar and D2 opens on it.
 */
const props = defineProps<{
  missionId: string;
  fleet: readonly FleetSpacecraft[];
  stations: readonly GroundStation[];
}>();
const emit = defineEmits<{ booked: [pass: Pass] }>();
const now = useNow();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const HOUR = 3_600_000;
const spacecraftId = ref("");
const range = ref<TimeRange>({ from: Date.now(), to: Date.now() + 24 * HOUR });
const direction = ref<"downlink" | "uplink">("downlink");
const stationIds = ref<string[]>([]);
const search = ref<Search | null>(null);
const searching = ref(false);
const searchError = ref<string | null>(null);
const chosen = ref<Offer | null>(null);
const note = ref("");
const booking = ref(false);
const result = ref<{ reserve: Reserve; offer: Offer } | null>(null);
const unclear = ref<string | null>(null);

const presets = computed<RangePreset[]>(() => {
  const t = now.value.getTime();
  return [6, 24, 72].map((h) => ({ id: `${h}h`, label: `Next ${h} h`, from: t, to: t + h * HOUR }));
});
const scOptions = computed(() =>
  props.fleet.map((sc) => ({ value: sc.id, label: `${sc.name} · SCID ${sc.scid}` })),
);
const directions = [
  { value: "downlink", label: "Downlink" },
  { value: "uplink", label: "With uplink" },
] as const;
const scName = computed(
  () => props.fleet.find((sc) => sc.id === spacecraftId.value)?.name ?? "this spacecraft",
);

function open(prefill: { spacecraftId?: string; from?: number; to?: number } = {}) {
  spacecraftId.value = prefill.spacecraftId ?? spacecraftId.value;
  const t = Date.now();
  range.value = { from: Math.max(prefill.from ?? t, t), to: prefill.to ?? t + 24 * HOUR };
  search.value = null;
  chosen.value = null;
  result.value = null;
  unclear.value = null;
  searchError.value = null;
  sheet.value?.open();
}
defineExpose({ open });

function toggleStation(id: string) {
  stationIds.value = stationIds.value.includes(id)
    ? stationIds.value.filter((s) => s !== id)
    : [...stationIds.value, id];
}
async function runSearch() {
  if (!spacecraftId.value || searching.value) return;
  searching.value = true;
  searchError.value = null;
  chosen.value = null;
  result.value = null;
  const r = await searchOffers(props.missionId, {
    spacecraftId: spacecraftId.value,
    from: new Date(range.value.from),
    to: new Date(range.value.to),
    direction: direction.value,
    stationIds: stationIds.value,
  });
  searching.value = false;
  if (r.ok) search.value = r.value;
  else searchError.value = describeApiError(r.error);
}
async function book() {
  const o = chosen.value;
  if (!o || booking.value) return;
  booking.value = true;
  unclear.value = null;
  const r = await reserveOffer(props.missionId, o.token, note.value);
  booking.value = false;
  if (r.ok) {
    result.value = { reserve: r.value, offer: o };
    return;
  }
  const e = r.error;
  if (isError(e, "opportunity_expired")) searchError.value = "That offer expired. Search again.";
  else if (isError(e, "route_changed"))
    searchError.value = "The route to that station changed. Search again.";
  // Nothing was booked: the signed offer didn't check out (tampered, or for another mission).
  else if (isError(e, "token_invalid"))
    searchError.value = "That offer can't be booked any more. Search again.";
  else if (e.kind === "forbidden") searchError.value = "Operators book passes.";
  else unclear.value = `It's unclear whether it was booked (${describeApiError(e)}).`;
}
const run = (f: () => Promise<void>) => () => f().catch((e: unknown) => console.error(e));
function showPass() {
  const p = result.value?.reserve.pass;
  sheet.value?.close();
  if (p) emit("booked", p);
}
const outcome = computed(() =>
  result.value ? outcomeWords(result.value.reserve, result.value.offer) : null,
);
</script>

<template>
  <ApSheet ref="sheet" title="Book a pass" width="wide" initial-focus="select">
    <div class="flex flex-wrap items-end gap-3">
      <ApSelect v-model="spacecraftId" label="Spacecraft" :options="scOptions" />
      <ApTimeRange v-model="range" label="Window" :presets="presets" />
      <ApSegmented v-model="direction" :options="directions" label="Direction" />
    </div>
    <div v-if="stations.length" role="group" aria-label="Stations" class="flex flex-wrap gap-1.5">
      <ApButton
        size="compact"
        :variant="stationIds.length === 0 ? 'primary' : 'ghost'"
        :aria-pressed="stationIds.length === 0"
        @click="stationIds = []"
        >Any</ApButton
      >
      <ApButton
        v-for="st in stations"
        :key="st.id"
        size="compact"
        :variant="stationIds.includes(st.id) ? 'primary' : 'ghost'"
        :aria-pressed="stationIds.includes(st.id)"
        @click="toggleStation(st.id)"
        >{{ st.code ?? st.display_name ?? st.id }}</ApButton
      >
    </div>
    <ApButton
      variant="secondary"
      :disabled="!spacecraftId || searching"
      :disabled-reason="searching ? 'Searching…' : 'Choose a spacecraft'"
      @click="run(runSearch)()"
      >{{ searching ? "Searching…" : "Search" }}</ApButton
    >
    <ApCallout v-if="searchError" tone="caution">{{ searchError }}</ApCallout>
    <template v-if="search">
      <p v-for="nr in search.not_ready" :key="nr.code" class="m-0 text-sm text-caution-text">
        {{ nr.message }}
      </p>
      <p v-if="search.hidden.no_uplink_route" class="m-0 text-sm text-text-3">
        {{ search.hidden.no_uplink_route }}
        {{ search.hidden.no_uplink_route === 1 ? "station" : "stations" }} hidden: no uplink route
        to {{ search.spacecraft.name }}.
      </p>
      <p v-if="search.offers.length === 0" class="m-0 text-text-3">{{ emptyWords(search) }}</p>
      <ul v-else class="m-0 flex list-none flex-col p-0" aria-label="Offers">
        <!-- By token: the same opportunity can come back once per ready route (qa 11-13). -->
        <li v-for="o in search.offers" :key="o.token" class="border-t border-hairline py-2">
          <button
            type="button"
            class="flex w-full cursor-pointer flex-wrap items-center gap-x-3 gap-y-1 border-0 bg-transparent p-0 text-left disabled:cursor-not-allowed disabled:opacity-60"
            :disabled="offerBlocked(o, now) !== null || result !== null"
            :aria-pressed="chosen?.token === o.token"
            @click="chosen = o"
          >
            <span class="font-mono text-readout">{{ stationWords(o) }}</span>
            <span class="text-text-3">{{ providerWords(o) }}</span>
            <span class="font-mono text-text-2">{{ windowWords(o) }}</span>
            <span class="font-mono text-text-3">{{
              formatDuration((Date.parse(o.ends_at) - Date.parse(o.starts_at)) / 1000)
            }}</span>
            <ApTag v-if="o.uplink_capable" state="neutral" label="Up" />
            <span
              class="ml-auto font-mono text-xs uppercase"
              :class="expiryWords(o, now).soon ? 'text-caution-text' : 'text-text-4'"
              >{{ expiryWords(o, now).text }}</span
            >
          </button>
          <p v-if="offerBlocked(o, now)" class="m-0 pt-1 text-sm text-text-3">
            {{ offerBlocked(o, now) }}
          </p>
          <div v-if="chosen?.token === o.token && !result" class="flex flex-col gap-2 pt-2">
            <p class="m-0 text-readout">{{ confirmLine(scName, o, direction) }}</p>
            <ApTextarea v-model="note" label="Why" :rows="2" placeholder="Optional" />
            <ApCallout v-if="unclear" tone="caution">{{ unclear }}</ApCallout>
            <div class="flex flex-col gap-1">
              <ApButton
                variant="primary"
                :disabled="booking || offerBlocked(o, now) !== null"
                disabled-reason="Booking…"
                @click="run(book)()"
                >{{ unclear ? "Try again" : "Book this pass" }}</ApButton
              >
              <p class="m-0 text-xs text-text-3">
                {{
                  unclear
                    ? "Reserving again won't book it twice."
                    : "Outside a plan: it doesn't count toward contact rules, and plans work around it."
                }}
              </p>
            </div>
          </div>
        </li>
      </ul>
      <p v-if="search.truncated" class="m-0 text-sm text-caution-text">
        More offers than fit; narrow the window or the stations.
      </p>
    </template>
    <ApCallout v-if="outcome" :tone="outcome.tone">{{ outcome.text }}</ApCallout>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Close</ApButton>
      <ApButton v-if="result?.reserve.pass" variant="primary" @click="showPass"
        >Show the pass</ApButton
      >
    </template>
  </ApSheet>
</template>
