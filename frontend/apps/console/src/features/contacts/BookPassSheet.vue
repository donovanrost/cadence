<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { describeApiError, isError, useRemoteQuery } from "@/api/index.ts";
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
  type TimeRange,
} from "@/ui";
import RoutePicker from "./RoutePicker.vue";
import { fetchRoutes, rangePresets, uplinkBlock, viaWords, windowProblem } from "./routes.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import type { Pass } from "./api.ts";
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
const props = defineProps<{ missionId: MissionId; fleet: readonly FleetSpacecraft[] }>();
const emit = defineEmits<{ booked: [pass: Pass] }>();
const now = useNow();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const HOUR = 3_600_000;
const spacecraftId = ref("");
const routeKeys = ref<string[]>([]);
/** A16b: the spacecraft's ready routes and the server's reach (how far ahead a search may go). */
const routes = useRemoteQuery(
  computed(() => (spacecraftId.value ? { m: props.missionId, sc: spacecraftId.value } : null)),
  (k, signal) => fetchRoutes(k.m, k.sc, signal),
);
const routeData = computed(() =>
  routes.state.value.status === "ready" ? routes.state.value.value : null,
);
/** A booking is future: the track runs now…the reach, so a drag can't pick a past window (U62). */
const track = computed(() => {
  const t = now.value.getTime();
  const until = routeData.value ? Date.parse(routeData.value.limits.reach_until) : t + 48 * HOUR;
  return { from: t, to: until };
});
const range = ref<TimeRange>({ from: Date.now(), to: Date.now() + 24 * HOUR });
const direction = ref<"downlink" | "uplink">("downlink");
const search = ref<Search | null>(null);
const searching = ref(false);
const searchError = ref<string | null>(null);
const chosen = ref<Offer | null>(null);
const note = ref("");
const booking = ref(false);
const result = ref<{ reserve: Reserve; offer: Offer } | null>(null);
const unclear = ref<string | null>(null);

const presets = computed(() =>
  rangePresets(now.value.getTime(), routeData.value?.limits.reach_until ?? null),
);
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

/** Why Search can't run: no spacecraft, a bad window, or only downlink routes for an uplink. */
const blocked = computed(
  () =>
    (spacecraftId.value ? null : "Choose a spacecraft") ??
    windowProblem(range.value, routeData.value?.limits ?? null, now.value.getTime()) ??
    uplinkBlock(
      routeData.value?.routes ?? [],
      routeKeys.value,
      direction.value === "uplink",
      scName.value,
    ),
);
async function runSearch() {
  if (blocked.value || searching.value) return;
  searching.value = true;
  searchError.value = null;
  chosen.value = null;
  result.value = null;
  const r = await searchOffers(props.missionId, {
    spacecraftId: spacecraftId.value,
    from: new Date(range.value.from),
    to: new Date(range.value.to),
    direction: direction.value,
    routeKeys: routeKeys.value,
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
      <ApTimeRange v-model="range" label="Window" :presets="presets" :span="track" />
      <ApSegmented v-model="direction" :options="directions" label="Direction" />
    </div>
    <p
      v-if="windowProblem(range, routeData?.limits ?? null, now.getTime())"
      class="m-0 text-sm text-caution-text"
    >
      {{ windowProblem(range, routeData?.limits ?? null, now.getTime()) }}
    </p>
    <p
      v-for="nr in routeData?.not_ready ?? []"
      :key="nr.code"
      class="m-0 text-sm text-caution-text"
    >
      {{ nr.message }}
    </p>
    <RoutePicker
      v-if="routeData?.routes.length"
      v-model="routeKeys"
      :routes="routeData.routes"
      :with-uplink="direction === 'uplink'"
      :spacecraft="scName"
    />
    <ApButton
      variant="secondary"
      :disabled="blocked !== null || searching"
      :disabled-reason="searching ? 'Searching…' : (blocked ?? '')"
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
      <p v-if="search.offers.length === 0" class="m-0 text-text-3">
        {{ emptyWords(search, viaWords(routeData?.routes ?? [], routeKeys)) }}
      </p>
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
            <!-- ux U69 A16a: the plan's tag; 'limited' says so, 'available' says nothing. -->
            <ApTag v-if="o.synthetic" state="stale" label="Synthetic" />
            <span v-if="o.availability === 'limited'" class="text-sm text-caution-text"
              >Limited availability</span
            >
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
        More offers than fit; narrow the window or the routes.
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
