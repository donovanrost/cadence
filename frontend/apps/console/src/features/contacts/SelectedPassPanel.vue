<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import {
  formatClock,
  formatCountdown,
  formatDuration,
  useNow,
  ApButton,
  ApEmptyState,
  ApKeyValue,
  ApPanel,
  ApTag,
} from "@/ui";
import {
  contactOpState,
  contactState,
  contactStateWord,
  sourceLabel,
} from "@/features/scheduling/index.ts";
import type { Pass } from "./api.ts";
import { stationLabel } from "./gantt.ts";

/**
 * D2 · Selected pass (Contacts.md): spacecraft + state, station and countdown, window, duration,
 * source. Max elevation, sky plot and downlink estimates are omitted (no propagation, DECISIONS #4);
 * Swap station / Release stay hidden until their endpoints exist.
 */
const props = defineProps<{
  pass: Pass | null;
  spacecraft: { name: string; scid: number } | null;
}>();
const now = useNow();

const state = computed(() => (props.pass ? contactState(props.pass) : null));
const tag = computed(() =>
  state.value === null
    ? null
    : { state: contactOpState(state.value), label: contactStateWord[state.value] },
);
/** K2: a rejected / failed reservation booked by a plan can be re-planned (lead, 4259c615). */
const replan = computed(() => {
  const p = props.pass;
  return p?.plan && (p.state === "rejected" || p.state === "failed")
    ? { name: "ops.contacts.replan", query: { plan: p.plan.id } }
    : null;
});
const facts = computed(() => {
  const p = props.pass;
  if (!p) return [];
  const from = new Date(p.starts_at);
  const to = new Date(p.ends_at);
  return [
    {
      key: "window",
      label: "Window",
      value: `${formatClock(from)} – ${formatClock(to)}Z`,
      mono: true,
    },
    {
      key: "duration",
      label: "Duration",
      value: formatDuration((to.getTime() - from.getTime()) / 1000),
      mono: true,
    },
    ...(p.max_elevation_deg === null
      ? []
      : [{ key: "el", label: "Max el", value: `${p.max_elevation_deg}°`, mono: true }]),
    ...(p.uplink_capable === null
      ? []
      : [
          {
            key: "link",
            label: "Link",
            value: p.uplink_capable ? "Uplink capable" : "Downlink only",
          },
        ]),
    { key: "source", label: "Source", value: sourceLabel(p.source, "contact") },
    { key: "station", label: "Station", value: p.station.name ?? stationLabel(p) },
  ];
});
const countdown = computed(() => {
  const p = props.pass;
  if (!p) return "";
  const aos = Date.parse(p.starts_at);
  return aos > now.value.getTime()
    ? `AOS ${formatCountdown(new Date(aos), now.value)}`
    : `LOS ${formatCountdown(new Date(p.ends_at), now.value)}`;
});
</script>

<template>
  <ApPanel index="D2" title="Selected pass" pane flush>
    <ApEmptyState
      v-if="!pass"
      headline="No pass selected"
      sentence="Choose a bar in the schedule."
    />
    <div v-else class="flex flex-col gap-3 p-4">
      <div class="flex flex-wrap items-center gap-3">
        <RouterLink
          v-if="spacecraft"
          :to="{ name: 'ops.spacecraft', params: { scId: String(spacecraft.scid) } }"
          class="max-md:hit-44 font-display text-lg font-semibold text-readout no-underline hover:underline"
          >{{ spacecraft.name }}</RouterLink
        >
        <ApTag v-if="tag" :state="tag.state" :label="tag.label" />
      </div>
      <p class="m-0 font-mono text-md text-text-2 uppercase">
        {{ pass.station.name ?? stationLabel(pass) }} ·
        <span class="text-readout">{{ countdown }}</span>
      </p>
      <ApKeyValue :items="facts" />
      <ApButton v-if="replan" size="compact" :to="replan">Re-plan</ApButton>
    </div>
  </ApPanel>
</template>
