<script setup lang="ts">
import { computed, onScopeDispose, ref, watch } from "vue";
import { useMissionScope } from "@/shell/index.ts";
import { useRemoteQuery } from "@/api/index.ts";
import {
  ApButton,
  ApCallout,
  ApChip,
  ApEmptyState,
  ApField,
  ApPanel,
  ApSelect,
  ApStatusMark,
  stateWord,
} from "@/ui";
import { describeApiError, type Scid } from "@/api/index.ts";
import { formatValue, withUnit } from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { fetchPoints, pointLimits, type TelemetryPoint } from "./api.ts";

/**
 * T1 · Spacecraft chips + point search (M23). An empty search lists the mission's points; with a
 * spacecraft chosen, each point shows its latest value and limit state. An exact id can still be
 * entered (the history read accepts any id).
 */
const props = defineProps<{
  fleet: readonly FleetSpacecraft[];
  scids: readonly Scid[];
  points: readonly string[];
}>();
const emit = defineEmits<{
  addSc: [scid: Scid];
  removeSc: [scid: Scid];
  addPoint: [pointId: string];
  removePoint: [pointId: string];
}>();
const scope = useMissionScope();

const pick = ref("");
const scOptions = computed(() => [
  { value: "", label: "Add spacecraft…" },
  ...props.fleet
    .filter((sc) => !props.scids.includes(sc.scid))
    .map((sc) => ({ value: String(sc.scid), label: sc.name })),
]);
function onPick(value: string) {
  const sc = props.fleet.find((row) => String(row.scid) === value);
  if (sc) emit("addSc", sc.scid);
  pick.value = "";
}
const nameOf = (scid: Scid) => props.fleet.find((sc) => sc.scid === scid)?.name ?? `SCID ${scid}`;

const q = ref("");
/** Debounced query (120 ms, Palette.md); empty lists the mission's points. */
const term = ref("");
let timer: ReturnType<typeof setTimeout> | null = null;
watch(q, (value) => {
  if (timer !== null) clearTimeout(timer);
  timer = setTimeout(() => {
    term.value = value.trim();
  }, 120);
});
onScopeDispose(() => {
  if (timer !== null) clearTimeout(timer);
});
const firstSc = computed(() => props.fleet.find((sc) => sc.scid === props.scids[0])?.id);
const search = useRemoteQuery(
  // A typed key (§12 A4): compared by value, no JSON round trip or cast.
  computed(() => ({ m: scope.value.mission.id, q: term.value, sc: firstSc.value ?? null })),
  (k, signal) => fetchPoints(k.m, { q: k.q, ...(k.sc ? { spacecraftId: k.sc } : {}) }, signal),
);
/** B2: the limit mark's word, for a screen reader (the mark itself is decorative). */
function limitWord(p: TelemetryPoint): string {
  const limits = pointLimits(p);
  return limits.word ?? stateWord(limits.mark);
}
// Null can mean the stored history couldn't be read (b8181eb9), so never "yet".
const latestText = (p: TelemetryPoint) =>
  p.latest ? (withUnit(formatValue(p.latest.value), p.unit) ?? "—") : "No recent value";

/** D12: the screen asks for a spacecraft by focusing the picker. */
const scPicker = ref<HTMLElement | null>(null);
defineExpose({ focusSpacecraft: () => scPicker.value?.querySelector("select")?.focus() });

const manual = ref("");
function addManual() {
  const id = manual.value.trim();
  if (id) emit("addPoint", id);
  manual.value = "";
}
</script>

<template>
  <ApPanel index="T1" title="Points" pane flush>
    <div class="flex flex-col gap-3 p-4">
      <div ref="scPicker" class="contents">
        <ApSelect
          :model-value="pick"
          label="Add spacecraft"
          hidden-label
          size="compact"
          :options="scOptions"
          @update:model-value="onPick"
        />
      </div>
      <ApField v-model="q" label="Search points" type="search" placeholder="Name or description" />
      <div v-if="scids.length" class="flex flex-wrap gap-1.5">
        <ApChip
          v-for="scid in scids"
          :key="scid"
          removable
          :remove-label="`Remove ${nameOf(scid)}`"
          @remove="emit('removeSc', scid)"
          >{{ nameOf(scid) }}</ApChip
        >
      </div>
      <div v-if="points.length" class="flex flex-wrap gap-1.5">
        <ApChip
          v-for="p in points"
          :key="p"
          removable
          :remove-label="`Remove ${p}`"
          @remove="emit('removePoint', p)"
          ><span class="normal-case">{{ p }}</span></ApChip
        >
      </div>
      <details class="border border-hairline">
        <summary class="ap-label flex min-h-11 cursor-pointer items-center px-3">
          Technical · exact point id
        </summary>
        <div class="flex flex-col gap-2 px-3 pb-3">
          <form class="flex items-end gap-2" @submit.prevent="addManual">
            <div class="min-w-0 flex-1">
              <ApField v-model="manual" label="Point id" mono placeholder="EPS.sa1_current" />
            </div>
            <ApButton
              size="compact"
              type="submit"
              :disabled="!manual.trim()"
              disabled-reason="Enter a point id first"
              >Add</ApButton
            >
          </form>
        </div>
      </details>
    </div>
    <ApCallout v-if="search.state.value.status === 'failed'" tone="caution">
      Couldn't search points: {{ describeApiError(search.state.value.error) }}
      <template #action><ApButton size="compact" @click="search.refetch">Retry</ApButton></template>
    </ApCallout>
    <ApEmptyState
      v-else-if="
        search.state.value.status === 'ready' && search.state.value.value.points.length === 0
      "
      :headline="term ? `No points match “${term}”` : 'No telemetry points in this mission yet'"
      :announce="term !== ''"
    />
    <ul v-else-if="search.state.value.status === 'ready'" class="m-0 list-none p-0">
      <li
        v-for="point in search.state.value.value.points"
        :key="point.id"
        class="border-t border-hairline"
      >
        <button
          type="button"
          class="flex min-h-11 w-full cursor-pointer flex-col px-4 py-2 text-left hover:bg-raised"
          @click="emit('addPoint', point.id)"
        >
          <span class="flex items-center gap-2 font-mono text-sm text-readout normal-case">
            <ApStatusMark v-if="point.latest" :state="pointLimits(point).mark" />
            {{ point.id }}
            <span v-if="point.latest" class="sr-only">, {{ limitWord(point) }}</span>
            <span v-if="points.includes(point.id)" class="text-xs text-text-4 uppercase"
              >added</span
            >
          </span>
          <span class="text-md text-text-3"
            ><template v-if="firstSc">{{ latestText(point) }} · </template
            >{{ point.description ?? point.subsystem ?? point.name
            }}{{ point.unit ? ` · ${point.unit}` : "" }}</span
          >
        </button>
      </li>
    </ul>
  </ApPanel>
</template>
