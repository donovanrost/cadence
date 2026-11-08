<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useMissionScope } from "@/shell/index.ts";
import { ApPanel, ApRemote } from "@/ui";
import { FleetMatrix, useFleet, type FleetSpacecraft } from "@/features/fleet/index.ts";
import ActionQueuePanel from "./ActionQueuePanel.vue";
import ConstellationPanel from "./ConstellationPanel.vue";
import LiveStatusCallout from "./LiveStatusCallout.vue";
import NowHeader from "./NowHeader.vue";
import NowStats from "./NowStats.vue";
import PassesPanel from "./PassesPanel.vue";
import { deriveQueue, nowHeadline } from "./queue.ts";

/** J1 · Now. Spec: docs/apogee/ux/screens/Now.md. Data: docs/apogee/api/ops.md (fleet). */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const fleet = useFleet(computed(() => scope.value.mission.id));

const snapshot = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value : null,
);
const queue = computed(() => (snapshot.value ? deriveQueue(snapshot.value) : []));
const headline = computed(() => {
  if (snapshot.value) return nowHeadline(snapshot.value, queue.value);
  return fleet.state.value.status === "failed"
    ? "Fleet status unavailable"
    : "Loading fleet status";
});

/** Guards don't reject in this app; a rejection is a bug worth surfacing in the console. */
function navigationFailed(error: unknown) {
  console.error("Navigation failed", error);
}

const selectedPlane = computed(() => {
  const plane = Number(route.query.plane);
  return Number.isInteger(plane) && plane > 0 ? plane : null;
});
function selectPlane(plane: number | null) {
  const { plane: _drop, ...rest } = route.query;
  router
    .replace({ query: plane === null ? rest : { ...rest, plane: String(plane) } })
    .catch(navigationFailed);
}
function openSpacecraft(sc: FleetSpacecraft) {
  router
    .push({ name: "ops.spacecraft", params: { scId: String(sc.scid) } })
    .catch(navigationFailed);
}
function openById(id: string) {
  const sc = snapshot.value?.spacecraft.find((row) => row.id === id);
  if (sc) openSpacecraft(sc);
}
</script>

<template>
  <!-- Console layout from 1100px up (holds still); below, the page scrolls (Now spec, layout). -->
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-[1100px]:overflow-auto">
    <NowHeader :mission-name="scope.mission.name" :headline="headline" :fleet="snapshot" />
    <LiveStatusCallout />
    <ApRemote :state="fleet.state.value" loading-label="LOADING FLEET…" @retry="fleet.refetch">
      <template #default="{ value }">
        <NowStats :fleet="value" />
        <div
          class="grid min-h-0 flex-1 grid-cols-[1.2fr_1fr] grid-rows-[minmax(0,1fr)_auto] gap-3 max-[1100px]:flex-none max-[1100px]:grid-rows-[minmax(320px,auto)_auto] max-[768px]:grid-cols-1 max-[768px]:grid-rows-none"
        >
          <ConstellationPanel
            class="max-[1100px]:h-[360px]"
            :spacecraft="value.spacecraft"
            :selected-plane="selectedPlane"
            @open="openById"
            @select-plane="selectPlane"
          />
          <ActionQueuePanel
            class="max-[1100px]:min-h-[320px] max-[768px]:order-first"
            :items="queue"
            :nominal="value.counts.nominal"
          />
          <ApPanel index="A3" title="Fleet matrix" :meta="`${value.counts.total} spacecraft`">
            <FleetMatrix
              :spacecraft="value.spacecraft"
              :selected-plane="selectedPlane"
              @open="openSpacecraft"
              @select-plane="selectPlane"
            />
            <RouterLink
              :to="{ name: 'ops.fleet' }"
              class="font-mono text-xs text-text-3 uppercase no-underline hover:text-readout"
              >View as table →</RouterLink
            >
          </ApPanel>
          <PassesPanel />
        </div>
      </template>
    </ApRemote>
  </div>
</template>
