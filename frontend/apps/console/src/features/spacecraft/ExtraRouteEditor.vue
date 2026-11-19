<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { KindEditor, type FormValues, type KindSchema } from "@/features/changes/index.ts";
import { fetchStations } from "@/features/stations/index.ts";
import { ApButton, ApCallout, ApRemote } from "@/ui";
import type { SpacecraftDetail } from "./detail.ts";
import { fetchExtraRoute, routeChangeSummary, routeSummary, stationWord } from "./routes.ts";

/**
 * U79: add (`new`) or edit one extra route of this spacecraft through the change set. The form is
 * the kind's generated one; the spacecraft is this page's (create-only, and the only choice).
 */
const props = defineProps<{ missionId: MissionId; detail: SpacecraftDetail; routeId: string }>();
const adding = computed(() => props.routeId === "new");
const spacecraft = computed(() => props.detail.spacecraft);
const route = useRemoteQuery(
  () =>
    adding.value
      ? null
      : { missionId: props.missionId, spacecraftId: spacecraft.value.id, routeId: props.routeId },
  fetchExtraRoute,
);
// The summary names the station by its code (U25); a failed stations read falls back to the name.
const stations = useRemoteQuery(() => props.missionId, fetchStations);
const stationById = computed(
  () =>
    new Map(
      stations.state.value.status === "ready"
        ? // compared-as-text: the form holds the chosen station id as text (FormValues).
          stations.state.value.value.map((s) => [String(s.id), s] as const)
        : [],
    ),
);
/**
 * A 404 (the route is gone, or this server can't read one yet) is said plainly with the way back,
 * not as a failure with a Retry that can't succeed (lead: no dead control).
 */
const missing = computed(
  () => route.state.value.status === "failed" && route.state.value.error.kind === "not_found",
);
const done = computed(() => ({
  name: "setup.spacecraft.one" as const,
  params: { spacecraftId: spacecraft.value.id },
}));

/** The spacecraft field offers only this page's spacecraft. */
function prepare(schema: KindSchema): KindSchema {
  // compared-as-text: schema enum values are raw JSON; this spacecraft's id as the same text.
  const own = String(spacecraft.value.id);
  return {
    ...schema,
    fields: schema.fields.map((f) =>
      f.path === "spacecraft_id" && f.enum
        ? { ...f, enum: f.enum.filter((o) => String(o.value) === own) }
        : f,
    ),
  };
}
function summarize(action: "create" | "update", values: FormValues): string {
  const station = stationById.value.get(values.ground_station_id ?? "");
  const word = station ? stationWord({ code: station.code, name: station.display_name }) : "";
  const where = word || "a station";
  if (action === "create") return routeSummary("Add", where, spacecraft.value.name);
  // The route's rendered name, as the routing list shows it (ux: quoted when it has one).
  const shown = props.detail.routing_rules.find((r) => r.route_id === props.routeId)?.name ?? null;
  return routeChangeSummary("Edit", shown, where, spacecraft.value.name);
}
</script>

<template>
  <KindEditor
    v-if="adding"
    :mission-id="missionId"
    kind="spacecraft_route"
    :entity-id="null"
    :document="{ spacecraft_id: spacecraft.id }"
    name="extra route"
    index="D4"
    surface="spacecraft"
    :done="done"
    :prepare="prepare"
    :summarize="summarize"
  />
  <ApCallout v-else-if="missing" tone="info">
    This extra route can't be opened for editing. It may have been removed.
    <template #action><ApButton size="compact" :to="done">Back to routing</ApButton></template>
  </ApCallout>
  <ApRemote
    v-else
    :state="route.state.value"
    loading-label="Loading extra route…"
    @retry="route.refetch"
  >
    <template #default="{ value }">
      <KindEditor
        :mission-id="missionId"
        kind="spacecraft_route"
        :entity-id="value.id"
        :document="value.document"
        name="extra route"
        index="D4"
        surface="spacecraft"
        :done="done"
        :prepare="prepare"
        :summarize="summarize"
      />
    </template>
  </ApRemote>
</template>
