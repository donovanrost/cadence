<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import {
  ApBreadcrumb,
  ApPageHeader,
  ApRemote,
  ApTabLinks,
  type ApCrumb,
  type ApTabLink,
} from "@/ui";
import AppStatusLine from "./AppStatusLine.vue";
import AppSurfaceNotice from "./AppSurfaceNotice.vue";
import { fetchApps } from "./api.ts";
import { fetchSurfaceHost } from "./host.ts";
import type { SaveOutcome } from "./saveOutcome.ts";
import { hostRefusal, setupSurfaces } from "./surfaces.ts";
import SurfaceMount from "./SurfaceMount.vue";

/**
 * L9 app surface host (ux screens/AppSurfaces.md, DECISIONS #75/#77): the host draws the label,
 * status, title, tabs, notices and states; the app renders only its body.
 */
const route = useRoute("setup.app");
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const appKey = computed(() => (typeof route.params.appKey === "string" ? route.params.appKey : ""));
const apps = useRemoteQuery(missionId, fetchApps);
const app = computed(() =>
  apps.state.value.status === "ready"
    ? (apps.state.value.value.apps.find((a) => a.key === appKey.value) ?? null)
    : null,
);
const surfaces = computed(() => setupSurfaces(app.value?.surfaces ?? []));
const surfaceId = computed(() =>
  typeof route.params.surface === "string" && route.params.surface
    ? route.params.surface
    : (surfaces.value[0]?.surface_id ?? null),
);
const key = computed(() =>
  surfaceId.value
    ? {
        missionId: missionId.value,
        appKey: appKey.value,
        surfaceId: surfaceId.value,
        spacecraftId: null,
      }
    : null,
);
const host = useRemoteQuery(key, fetchSurfaceHost);
/** api: without `applications:operate` the surface renders read-only, with the host's notice. */
const canEdit = computed(
  () =>
    host.state.value.status === "ready" &&
    host.state.value.value.catalog.session.context.actor.permissions.includes(
      "applications:operate",
    ),
);
const readOnly = computed(() => host.state.value.status === "ready" && !canEdit.value);
/** Re-pin the app-host session (lead): the same read, outside the query so the surface stays mounted. */
async function repin() {
  const k = key.value;
  if (!k) return null;
  const r = await fetchSurfaceHost(k, new AbortController().signal);
  return r.ok ? r.value.catalog.session : null;
}
const outcome = ref<SaveOutcome | null>(null);
watch(surfaceId, () => (outcome.value = null));
const name = computed(() => app.value?.name ?? appKey.value);
const title = computed(
  () => surfaces.value.find((s) => s.surface_id === surfaceId.value)?.label ?? name.value,
);
const status = computed(() =>
  host.state.value.status === "ready" ? host.state.value.value.status : (app.value?.status ?? null),
);
const refusal = computed(() =>
  host.state.value.status === "failed" ? hostRefusal(host.state.value.error) : null,
);
const links = computed((): readonly ApTabLink[] =>
  surfaces.value.map((s) => ({
    key: s.surface_id,
    label: s.label,
    to: { name: "setup.app", params: { appKey: appKey.value, surface: s.surface_id } },
  })),
);
const crumbs = computed((): readonly ApCrumb[] => [
  { label: "Apps", to: { name: "setup.apps" } },
  { label: name.value },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader :label="`${scope.mission.name} · apps · ${name}`" :title="title" size="reading">
      <AppStatusLine :app-key="appKey" :status="status" />
    </ApPageHeader>
    <ApTabLinks
      v-if="links.length > 1"
      :links="links"
      :active="surfaceId ?? ''"
      label="App pages"
    />
    <AppSurfaceNotice
      :app-name="name"
      :mission-name="scope.mission.name"
      :refusal="refusal"
      :no-surface="apps.state.value.status === 'ready' && !surfaceId"
      :read-only="readOnly"
      :outcome="outcome"
    />
    <ApRemote
      v-if="!refusal && surfaceId"
      :state="host.state.value"
      :loading-label="`Loading ${name}…`"
      @retry="host.refetch"
    >
      <template #default="{ value }">
        <SurfaceMount
          :key="surfaceId"
          :host="value"
          :app-name="name"
          :repin="repin"
          @outcome="outcome = $event"
        />
      </template>
    </ApRemote>
  </div>
</template>
