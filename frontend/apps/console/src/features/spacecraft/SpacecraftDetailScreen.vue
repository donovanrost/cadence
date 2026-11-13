<script setup lang="ts">
import { SpacecraftApps } from "@/features/apps/index.ts";
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApButton, ApPageHeader, ApRemote, ApTag, type ApCrumb } from "@/ui";
import SpacecraftPanels from "./SpacecraftPanels.vue";
import { fetchSpacecraftDetail } from "./detail.ts";

/** Setup › Spacecraft › one (ux U6: Profile layout, `Open in Ops →`). */
const route = useRoute("setup.spacecraft.one");
const scope = useMissionScope();
const spacecraftId = computed(() =>
  typeof route.params.spacecraftId === "string" ? route.params.spacecraftId : null,
);
const key = computed(() =>
  spacecraftId.value
    ? { missionId: scope.value.mission.id, spacecraftId: spacecraftId.value }
    : null,
);
const { state, refetch } = useRemoteQuery(key, fetchSpacecraftDetail);
useMissionInvalidation(
  computed(() => scope.value.mission.id),
  ["spacecraft"],
  refetch,
);

const title = computed(() =>
  state.value.status === "ready" ? state.value.value.spacecraft.name : "Spacecraft",
);
// Ops addresses a spacecraft by SCID (fe-ops `ops.spacecraft`).
const opsScid = computed(() =>
  state.value.status === "ready" && state.value.value.spacecraft.scid !== null
    ? String(state.value.value.spacecraft.scid)
    : null,
);
const crumbs = computed((): readonly ApCrumb[] => [
  { label: "Spacecraft", to: { name: "setup.spacecraft" } },
  { label: title.value },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader :title="title" size="reading">
      <template v-if="state.status === 'ready'" #status>
        <ApTag v-if="state.value.readiness.ready" state="nominal" label="Ready" />
        <ApTag v-else state="caution" label="Incomplete" />
      </template>
      <ApButton v-if="opsScid" :to="{ name: 'ops.spacecraft', params: { scId: opsScid } }"
        >Open in Ops →</ApButton
      >
    </ApPageHeader>
    <ApRemote :state="state" loading-label="Loading spacecraft…" @retry="refetch">
      <template #default="{ value }"><SpacecraftPanels :detail="value" /></template>
    </ApRemote>
    <SpacecraftApps
      v-if="spacecraftId"
      :mission-id="scope.mission.id"
      :spacecraft-id="spacecraftId"
    />
  </div>
</template>
