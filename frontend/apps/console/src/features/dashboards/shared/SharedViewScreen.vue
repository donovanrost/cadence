<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, type LocationQueryValue } from "vue-router";
import { paramText, TakeoverHeader, useMissionScope } from "@/shell";
import { ApEmptyState, ApRemote, formatShort } from "@/ui";
import type { Runtime } from "../api.ts";
import { selectionFromQuery, selectionParams } from "../model/time-range.ts";
import CockpitStatus from "../viewer/CockpitStatus.vue";
import DashboardGrid from "../viewer/DashboardGrid.vue";
import InspectSheet from "../viewer/InspectSheet.vue";
import { useLiveRead } from "../viewer/useDashboardView.ts";
import { endedLink, fetchShare, fetchSnapshot, type EndedLink, type SharedView } from "./api.ts";
import DefinitionGrid from "./DefinitionGrid.vue";

/**
 * A share link or a snapshot (ux § Snapshots and shares): the viewer without Edit. A share is
 * live on the current version; a snapshot is fixed to its version and window (no live data).
 */
const route = useRoute();
const scope = useMissionScope();
const one = (v: LocationQueryValue | LocationQueryValue[] | undefined) =>
  typeof v === "string" ? v : "";
const missionId = computed(() => scope.value.mission.id);
const isShare = computed(() => route.name === "ops.dashboards.share");
const id = computed(() => paramText(route.params, isShare.value ? "shareId" : "snapshotId"));
const selection = computed(() => selectionFromQuery(one(route.query.from), one(route.query.to)));
const runtime = computed<Runtime>(() => {
  const p = selectionParams(selection.value);
  return { from: p.from ?? "", to: p.to ?? "", spacecraftId: one(route.query.spacecraft) };
});
const key = computed(() =>
  id.value ? JSON.stringify([missionId.value, isShare.value, id.value, runtime.value]) : null,
);
const query = useLiveRead(
  missionId,
  key,
  (signal) =>
    isShare.value
      ? fetchShare(missionId.value, id.value, runtime.value, signal)
      : fetchSnapshot(missionId.value, id.value, signal),
  {
    refreshMs: computed(() => (isShare.value ? 2_000 : null)),
    sliding: computed(() => selection.value.kind !== "absolute"),
    paused: ref(false),
  },
);
const view = computed(() =>
  query.state.value.status === "ready" ? query.state.value.value : null,
);
const ended = computed(() =>
  query.state.value.status === "failed" ? endedLink(query.state.value.error) : null,
);
const ENDED: Readonly<Record<EndedLink["kind"], string>> = {
  revoked: "This share link was revoked.",
  expired: "This share link has expired.",
  deleted: "This snapshot was deleted.",
};
const inspect = ref<InstanceType<typeof InspectSheet> | null>(null);

const when = (iso: string) => formatShort(new Date(iso));
/** ux header lines: `SHARED · live · expires 11-20` / `SNAPSHOT · window · v7 · taken by … at …`. */
function headerLine(v: SharedView | null): string {
  if (!v) return isShare.value ? "SHARED" : "SNAPSHOT";
  if (v.share)
    return `SHARED · live · ${v.share.expires_at ? `expires ${when(v.share.expires_at).slice(0, 5)}` : "no expiry"}`;
  const s = v.snapshot_row;
  if (!s) return "SNAPSHOT";
  const window = s.window ? `${when(s.window.from)}–${when(s.window.to)}` : "current data";
  const by = s.created_by?.name
    ? ` · taken by ${s.created_by.name} at ${when(s.created_at)}`
    : ` · taken ${when(s.created_at)}`;
  return `SNAPSHOT · ${window} · v${s.version}${by}`;
}
</script>

<template>
  <TakeoverHeader
    :title="view?.dashboard.name ?? 'Dashboard'"
    :context="headerLine(view)"
    :close="{ name: 'ops.dashboards' }"
    close-label="Close"
    title-as="h1"
  >
    <template #clocks><CockpitStatus /></template>
  </TakeoverHeader>
  <ApEmptyState v-if="ended" :headline="ENDED[ended.kind]" :sentence="ended.message" state="off" />
  <ApRemote v-else :state="query.state.value" @retry="query.refetch">
    <template #default="{ value }">
      <DashboardGrid
        v-if="value.snapshot"
        :snapshot="value.snapshot"
        @inspect="inspect?.open($event)"
      />
      <DefinitionGrid v-else-if="value.definition" :definition="value.definition" />
      <ApEmptyState
        v-else
        headline="Nothing saved yet."
        sentence="This dashboard has no saved version to show."
      />
    </template>
  </ApRemote>
  <InspectSheet ref="inspect" />
</template>
