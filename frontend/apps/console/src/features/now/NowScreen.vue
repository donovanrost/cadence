<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useMissionScope, useSession } from "@/shell/index.ts";
import { ApPanel, ApRemote } from "@/ui";
import {
  TelemetryDegraded,
  FleetMatrix,
  FleetStatStrip,
  layoutMatrix,
  matrixNaturalHeight,
  useFleet,
  type FleetSpacecraft,
} from "@/features/fleet/index.ts";
import ActionQueuePanel from "./ActionQueuePanel.vue";
import ConstellationPanel from "./ConstellationPanel.vue";
import LiveStatusCallout from "./LiveStatusCallout.vue";
import NowHeader from "./NowHeader.vue";
import PassesPanel from "./PassesPanel.vue";
import { nowHeadline } from "./queue.ts";
import { useActionQueue } from "./useActionQueue.ts";

/** J1 · Now. Spec: docs/apogee/ux/screens/Now.md. Data: docs/apogee/api/ops.md (fleet). */
const scope = useMissionScope();
const route = useRoute();
const router = useRouter();
const fleet = useFleet(computed(() => scope.value.mission.id));

const snapshot = computed(() =>
  fleet.state.value.status === "ready" ? fleet.state.value.value : null,
);
/** A3's panel chrome around the matrix rows: header, body padding, footer row, borders. */
const A3_CHROME_PX = 124;
/** Row 2 takes what the matrix needs at 16px cells, capped so A1/A2 keep ≥55% (ux review). */
const a3Need = computed(() => {
  const rows = snapshot.value ? layoutMatrix(snapshot.value.spacecraft).rows.length : 0;
  return `${matrixNaturalHeight(rows) + A3_CHROME_PX}px`;
});
const session = useSession();
const actionQueue = useActionQueue(
  computed(() => scope.value.mission.id),
  computed(() => scope.value.mission.name),
  session.user.id,
);
const queue = computed(() =>
  actionQueue.items.value.status === "ready" ? actionQueue.items.value.value : [],
);
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
  router.push({ name: "ops.spacecraft", params: { scId: sc.scid } }).catch(navigationFailed);
}
function openById(id: string) {
  const sc = snapshot.value?.spacecraft.find((row) => row.id === id);
  if (sc) openSpacecraft(sc);
}
</script>

<template>
  <!-- Console layout from the `console` breakpoint up (holds still); below, the page scrolls. -->
  <div class="flex min-h-0 flex-1 flex-col gap-3 max-console:overflow-auto">
    <NowHeader
      :mission-id="scope.mission.id"
      :mission-name="scope.mission.name"
      :headline="headline"
      :fleet="snapshot"
    />
    <LiveStatusCallout />
    <ApRemote :state="fleet.state.value" loading-label="LOADING FLEET…" @retry="fleet.refetch">
      <template #default="{ value }">
        <TelemetryDegraded :telemetry="value.telemetry" />
        <FleetStatStrip :fleet="value" linked />
        <div
          class="grid grid-cols-1 gap-3 md:grid-cols-[1.2fr_1fr] console:min-h-0 console:flex-1 console:grid-rows-[minmax(0,1fr)_min(var(--a3-need),45%)]"
          :style="{ '--a3-need': a3Need }"
        >
          <ConstellationPanel
            class="h-[360px] max-md:hidden console:h-auto"
            :spacecraft="value.spacecraft"
            :selected-plane="selectedPlane"
            @open="openById"
            @select-plane="selectPlane"
          />
          <ActionQueuePanel
            class="order-first min-h-[320px] md:order-none console:min-h-0"
            :state="actionQueue.items.value"
            :unshown="actionQueue.unshown.value"
            @retry="actionQueue.refetch"
            @retried="actionQueue.applyRetry"
            :nominal="value.counts.nominal"
          />
          <ApPanel
            index="A3"
            title="Fleet matrix"
            :meta="`${value.counts.total} spacecraft`"
            pane
            class="h-[460px] max-md:hidden console:h-auto"
          >
            <FleetMatrix
              fit-height
              table-link
              :spacecraft="value.spacecraft"
              :selected-plane="selectedPlane"
              @open="openSpacecraft"
              @select-plane="selectPlane"
            />
          </ApPanel>
          <PassesPanel class="max-md:hidden" :spacecraft="value.spacecraft" />
        </div>
      </template>
    </ApRemote>
  </div>
</template>
