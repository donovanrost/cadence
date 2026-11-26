<script setup lang="ts">
import { scidParam } from "@/api/index.ts";
import type { SpacecraftTab } from "@/shell";
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useFleetPosture, useMissionScope } from "@/shell/index.ts";
import { ApButton, ApEmptyState, ApPanel, ApRemote } from "@/ui";
import { useFleet } from "@/features/fleet/index.ts";
import InvestigateTab from "./InvestigateTab.vue";
import NotBuiltTab from "./NotBuiltTab.vue";
import HistoryTab from "./history/HistoryTab.vue";
import UplinkTab from "./uplink/UplinkTab.vue";
import PassesTab from "./passes/PassesTab.vue";
import ConfigurationTab from "./configuration/ConfigurationTab.vue";
import TelemetryTab from "./telemetry/TelemetryTab.vue";
import SpacecraftHeader from "./SpacecraftHeader.vue";
import { heroStatus, neighbours } from "./model.ts";
import { useSpacecraftAlarms } from "./useInvestigate.ts";

/** Spacecraft detail (route ops.spacecraft): shared header + tabs; J2 Investigate is the first tab. */
const scope = useMissionScope();
const route = useRoute("ops.spacecraft");
const missionId = computed(() => scope.value.mission.id);
const fleet = useFleet(missionId);
/** Ground limits configured, from the shell's /counts posture (#847); assumed until it answers. */
const posture = useFleetPosture();

const scid = computed(() => scidParam(route.params.scId));
const tab = computed((): SpacecraftTab => route.params.tab || "investigate");
/** The spacecraft id (not the SCID in the route) for the alarm read. */
const spacecraftId = computed(() => {
  const s = fleet.state.value;
  return s.status === "ready"
    ? (s.value.spacecraft.find((row) => row.scid === scid.value)?.id ?? null)
    : null;
});
/** Owned here so the header's status and the Investigate tab agree on one read. */
const alarms = useSpacecraftAlarms(missionId, spacecraftId);
const lookup = computed(() => {
  const state = fleet.state.value;
  if (state.status !== "ready") return null;
  const sc = state.value.spacecraft.find((row) => row.scid === scid.value) ?? null;
  if (!sc) return null;
  const a = alarms.state.value;
  return {
    sc,
    ...neighbours(state.value.spacecraft, sc),
    hero: heroStatus(sc, a.status === "ready" ? a.value.alarms : null),
  };
});
</script>

<template>
  <!-- Console layout from the `console` breakpoint up; below it the whole screen scrolls. -->
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <ApRemote :state="fleet.state.value" loading-label="LOADING SPACECRAFT…" @retry="fleet.refetch">
      <template #default>
        <template v-if="lookup">
          <SpacecraftHeader
            :sc="lookup.sc"
            :hero="lookup.hero"
            :prev="lookup.prev"
            :next="lookup.next"
            :tab="tab"
          />
          <InvestigateTab
            v-if="tab === 'investigate'"
            :key="lookup.sc.id"
            :sc="lookup.sc"
            :alarms="alarms.state.value"
            :more="{
              load: () => void alarms.more(),
              busy: alarms.moreBusy.value,
              failed: alarms.moreError.value !== null,
            }"
            :limits-configured="posture?.limits_configured !== false"
            :fleet="fleet.state.value.status === 'ready' ? fleet.state.value.value.spacecraft : []"
            @retry="alarms.refetch"
          />
          <TelemetryTab
            v-else-if="tab === 'telemetry'"
            :key="`t-${lookup.sc.id}`"
            :sc="lookup.sc"
          />
          <ConfigurationTab
            v-else-if="tab === 'configuration'"
            :key="`c-${lookup.sc.id}`"
            :sc="lookup.sc"
          />
          <PassesTab v-else-if="tab === 'passes'" :key="`p-${lookup.sc.id}`" :sc="lookup.sc" />
          <UplinkTab v-else-if="tab === 'uplink'" :key="`u-${lookup.sc.id}`" :sc="lookup.sc" />
          <HistoryTab v-else-if="tab === 'history'" :key="`h-${lookup.sc.id}`" :sc="lookup.sc" />
          <NotBuiltTab v-else :tab="tab" :sc="lookup.sc" />
        </template>
        <ApPanel v-else index="A1" title="Spacecraft" flush>
          <ApEmptyState
            headline="Spacecraft not found"
            :sentence="`No spacecraft with SCID ${scid} in ${scope.mission.name}.`"
          >
            <ApButton size="compact" :to="{ name: 'ops.fleet' }">Back to fleet</ApButton>
          </ApEmptyState>
        </ApPanel>
      </template>
    </ApRemote>
  </div>
</template>
