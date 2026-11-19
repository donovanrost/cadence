<script setup lang="ts">
import { SpacecraftApps } from "@/features/apps/index.ts";
import { computed } from "vue";
import { useRoute } from "vue-router";
import { spacecraftIdParam, useRemoteQuery } from "@/api";
import { useMissionInvalidation } from "@/live";
import { canAdministerOrganization, useMissionScope, useSession } from "@/shell";
import { ApBreadcrumb, ApButton, ApPageHeader, ApRemote, ApTag, type ApCrumb } from "@/ui";
import SpacecraftAdmin from "./SpacecraftAdmin.vue";
import ExtraRouteEditor from "./ExtraRouteEditor.vue";
import SpacecraftEditor from "./SpacecraftEditor.vue";
import SpacecraftPanels from "./SpacecraftPanels.vue";
import { fetchSpacecraftDetail } from "./detail.ts";
import { CONFIGURATION_WORKSPACE_LIVE } from "./configuration/api.ts";

/** Setup › Spacecraft › one (ux U6: Profile layout, `Open in Ops →`). */
const route = useRoute("setup.spacecraft.one");
const scope = useMissionScope();
const session = useSession();
/** L17: Edit and Archive stage into the change set (the same gate as stations' edits). */
const canStage = computed(() => canAdministerOrganization(session, scope.value.organization));
const editing = computed(() => canStage.value && route.query.edit === "1");
/** U79: `?route=new` adds an extra route, `?route=<id>` edits one (Routing's Add / Edit). */
const routeId = computed(() =>
  canStage.value && typeof route.query.route === "string" && route.query.route !== ""
    ? route.query.route
    : null,
);
/** The spacecraft's id (not its SCID): a branded SpacecraftId (typing §12C). */
const spacecraftId = computed(() => spacecraftIdParam(route.params.spacecraftId));
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

/** Spacecraft.md (#313, #316): the header names the craft with its SCID, "EARENDIL-312 · SCID 312". */
const title = computed(() => {
  if (state.value.status !== "ready") return "Spacecraft";
  const sc = state.value.value.spacecraft;
  return sc.scid === null ? sc.name : `${sc.name} · SCID ${sc.scid}`;
});
// Ops addresses a spacecraft by SCID (fe-ops `ops.spacecraft`).
const opsScid = computed(() =>
  state.value.status === "ready" && state.value.value.spacecraft.scid !== null
    ? state.value.value.spacecraft.scid
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
      <SpacecraftAdmin
        v-if="canStage && state.status === 'ready'"
        :mission-id="scope.mission.id"
        :detail="state.value"
        :editing="editing"
      />
      <!-- (B) U94: the craft's configuration workspace, once its GET is live. -->
      <ApButton
        v-if="CONFIGURATION_WORKSPACE_LIVE && spacecraftId"
        :to="{ name: 'setup.spacecraft.configuration', params: { spacecraftId } }"
        >Configuration</ApButton
      >
      <ApButton v-if="opsScid !== null" :to="{ name: 'ops.spacecraft', params: { scId: opsScid } }"
        >Open in Ops →</ApButton
      >
    </ApPageHeader>
    <ApRemote :state="state" loading-label="Loading spacecraft…" @retry="refetch">
      <template #default="{ value }">
        <SpacecraftEditor v-if="editing" :mission-id="scope.mission.id" :detail="value" />
        <ExtraRouteEditor
          v-else-if="routeId !== null"
          :key="routeId"
          :mission-id="scope.mission.id"
          :detail="value"
          :route-id="routeId"
        />
        <SpacecraftPanels
          v-else
          :mission-id="scope.mission.id"
          :detail="value"
          :can-stage="canStage"
        />
      </template>
    </ApRemote>
    <SpacecraftApps
      v-if="spacecraftId"
      :mission-id="scope.mission.id"
      :spacecraft-id="spacecraftId"
    />
  </div>
</template>
