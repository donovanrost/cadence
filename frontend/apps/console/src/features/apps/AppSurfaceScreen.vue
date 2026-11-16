<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useRemoteQuery, type SpacecraftId } from "@/api";
import { paramText, useMissionScope } from "@/shell";
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
import { fetchScopedApps } from "./api.ts";
import { fetchSurfaceHost } from "./host.ts";
import type { SaveOutcome } from "./saveOutcome.ts";
import { hostRefusal, retiredSurfaceHome, setupSurfaces } from "./surfaces.ts";
import SurfaceMount from "./SurfaceMount.vue";

/**
 * L9 app surface host (ux screens/AppSurfaces.md, DECISIONS #75/#77): the host draws the label,
 * status, title, tabs, notices and states; the app renders only its body. With `spacecraftId`
 * (L19, `setup.spacecraft.app`) it hosts the app's spacecraft-scope surfaces for that spacecraft.
 */
const props = defineProps<{ spacecraftId?: SpacecraftId | null }>();
const route = useRoute();
const spacecraftId = computed(() => props.spacecraftId ?? null);
const router = useRouter();
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const appKey = computed(() => paramText(route.params, "appKey"));
const apps = useRemoteQuery(
  () => ({ missionId: missionId.value, spacecraftId: spacecraftId.value }),
  fetchScopedApps,
);
const app = computed(() =>
  apps.state.value.status === "ready"
    ? (apps.state.value.value.apps.find((a) => a.key === appKey.value) ?? null)
    : null,
);
const surfaces = computed(() => setupSurfaces(app.value?.surfaces ?? []));
// A retired surface (a bookmark or an old link) goes to its console home, never an empty tab (ux).
watch(
  () => retiredSurfaceHome(appKey.value, paramText(route.params, "surface"), spacecraftId.value),
  (home) => {
    if (home) void router.replace(home).catch(() => undefined);
  },
  { immediate: true },
);
const surfaceId = computed(
  () => paramText(route.params, "surface") || (surfaces.value[0]?.surface_id ?? null),
);
const key = computed(() =>
  surfaceId.value
    ? {
        missionId: missionId.value,
        appKey: appKey.value,
        surfaceId: surfaceId.value,
        spacecraftId: spacecraftId.value,
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
    to: spacecraftId.value
      ? {
          name: "setup.spacecraft.app",
          params: { spacecraftId: spacecraftId.value, appKey: appKey.value, surface: s.surface_id },
        }
      : { name: "setup.app", params: { appKey: appKey.value, surface: s.surface_id } },
  })),
);
const crumbs = computed((): readonly ApCrumb[] =>
  spacecraftId.value
    ? [
        { label: "Spacecraft", to: { name: "setup.spacecraft" } },
        {
          label: spacecraftId.value,
          to: { name: "setup.spacecraft.one", params: { spacecraftId: spacecraftId.value } },
        },
        { label: name.value },
      ]
    : [{ label: "Apps", to: { name: "setup.apps" } }, { label: name.value }],
);
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
