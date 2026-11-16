<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { useRemoteQuery } from "@/api";
import { KindEditor, type FormValues, type KindSchema } from "@/features/changes/index.ts";
import { fetchStations } from "@/features/stations/index.ts";
import { ApRemote } from "@/ui";
import type { SpacecraftDetail } from "./detail.ts";
import { fetchExtraRoute, routeSummary, stationWord } from "./routes.ts";

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
  return routeSummary(
    action === "create" ? "Add" : "Edit",
    word || "a station",
    spacecraft.value.name,
  );
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
