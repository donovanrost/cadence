<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApStatusMark, plural } from "@/ui";
import { stationCode, type PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";
import type { StationHits, UnavailablePass } from "./unavailable.ts";

/**
 * D · station issues (ux U26): a drafted pass inside an outage/maintenance window is a conflict
 * (Remove, or look for another window); inside a degraded window it's at risk (no block).
 */
const props = defineProps<{
  plan: PlanDetail;
  hits: StationHits;
  nameOf: (id: string | null) => SpacecraftName | null;
  editable: boolean;
  busy: boolean;
}>();
defineEmits<{ remove: [snapshotId: string]; focus: [spacecraftId: string] }>();

type Group = { key: string; blocking: boolean; hits: UnavailablePass[] };
const groups = computed<Group[]>(() => {
  const map = new Map<string, Group>();
  for (const [list, blocking] of [
    [props.hits.blocking, true],
    [props.hits.atRisk, false],
  ] as const)
    for (const h of list) {
      const key = h.windowId ?? `${h.kind}:${h.snapshotId}`;
      const g = map.get(key) ?? { key, blocking, hits: [] };
      g.hits.push(h);
      map.set(key, g);
    }
  return [...map.values()].sort((a, b) => Number(b.blocking) - Number(a.blocking));
});
const passOf = (id: string) => props.plan.passes.find((p) => p.snapshot_id === id) ?? null;
const hhmm = (t: string | null) => (t ? `${t.slice(11, 16)}Z` : "open-ended");
function headline(g: Group): string {
  const first = g.hits[0];
  if (!first) return "";
  const p = passOf(first.snapshotId);
  const code = p ? stationCode(p.station) : "Station";
  const w = first.window;
  const span = w
    ? w.to
      ? ` ${w.from.slice(11, 16)}–${w.to.slice(11, 16)}Z`
      : ` from ${hhmm(w.from)}, no end reported`
    : "";
  return g.blocking
    ? `${code} is down${span} (${first.kind || "unavailable"}) · ${plural(g.hits.length, "drafted pass", "drafted passes")} ${g.hits.length === 1 ? "falls" : "fall"} in it`
    : `${code} is degraded${span} · ${plural(g.hits.length, "pass", "passes")} may lose data`;
}
const reportedAfter = (g: Group) => {
  const at = g.hits[0]?.window?.reported_at;
  return at && Date.parse(at) > Date.parse(props.plan.updated_at)
    ? `Reported ${at.slice(11, 16)}Z, after this draft.`
    : null;
};
</script>

<template>
  <section v-if="groups.length > 0" aria-label="Station issues" class="mb-4 flex flex-col gap-2">
    <div
      v-for="g in groups"
      :key="g.key"
      class="flex flex-col gap-1.5 px-3 py-2.5"
      :class="g.blocking ? 'bg-[var(--apogee-wash-crit)]' : 'bg-[var(--apogee-wash-caution)]'"
    >
      <p class="m-0 flex items-start gap-2 text-md text-readout">
        <ApStatusMark :state="g.blocking ? 'crit' : 'caution'" class="mt-1.5" />
        <span>{{ headline(g) }}</span>
      </p>
      <p v-if="reportedAfter(g)" class="m-0 font-mono text-xs text-text-3 uppercase">
        {{ reportedAfter(g) }}
      </p>
      <ul class="m-0 flex list-none flex-col gap-1 p-0">
        <li
          v-for="h in g.hits"
          :key="h.snapshotId"
          class="flex flex-wrap items-center gap-2 font-mono text-sm"
        >
          <span class="flex-1 text-text-2">
            {{
              nameOf(passOf(h.snapshotId)?.spacecraft_id ?? null)?.name ??
              passOf(h.snapshotId)?.spacecraft_id ??
              "?"
            }}
            {{ hhmm(passOf(h.snapshotId)?.starts_at ?? null) }}
          </span>
          <template v-if="editable && g.blocking">
            <ApButton
              size="compact"
              :disabled="busy"
              @click="$emit('focus', passOf(h.snapshotId)?.spacecraft_id ?? '')"
              >Other windows</ApButton
            >
            <ApButton
              size="compact"
              :disabled="busy || passOf(h.snapshotId)?.locked === true"
              @click="$emit('remove', h.snapshotId)"
              >Remove</ApButton
            >
          </template>
        </li>
      </ul>
    </div>
  </section>
</template>
