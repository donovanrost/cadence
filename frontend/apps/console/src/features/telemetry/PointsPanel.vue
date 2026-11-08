<script setup lang="ts">
import { computed, onScopeDispose, ref, watch } from "vue";
import { useMissionScope } from "@/shell/index.ts";
import { useRemoteQuery } from "@/api/index.ts";
import { ApButton, ApChip, ApEmptyState, ApField, ApPanel, ApSelect } from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { fetchPoints } from "./api.ts";

/**
 * T1 · Spacecraft chips + point search. Until the point-search read exists (M23) the list says so
 * and a point id can be entered directly (the history read accepts any id).
 */
const props = defineProps<{
  fleet: readonly FleetSpacecraft[];
  scids: readonly number[];
  points: readonly string[];
}>();
const emit = defineEmits<{
  addSc: [scid: number];
  removeSc: [scid: number];
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
  if (value) emit("addSc", Number(value));
  pick.value = "";
}
const nameOf = (scid: number) => props.fleet.find((sc) => sc.scid === scid)?.name ?? `SCID ${scid}`;

const q = ref("");
/** Debounced query (120 ms, Palette.md); empty means no request, so loading the page never 404s. */
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
  computed(() =>
    term.value === ""
      ? null
      : JSON.stringify({ m: scope.value.mission.id, q: term.value, sc: firstSc.value ?? "" }),
  ),
  (k, signal) => {
    // Sound: produced by JSON.stringify above.
    const { m, q: text, sc } = JSON.parse(k) as { m: string; q: string; sc: string };
    return fetchPoints(m, { q: text, ...(sc ? { spacecraftId: sc } : {}) }, signal);
  },
);
const searchMissing = computed(
  () => search.state.value.status === "failed" && search.state.value.error.kind === "not_found",
);

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
      <ApSelect
        :model-value="pick"
        label="Add spacecraft"
        hidden-label
        size="compact"
        :options="scOptions"
        @update:model-value="onPick"
      />
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
      <ApField v-model="q" label="Search points" type="search" placeholder="Name or description" />
    </div>
    <ApEmptyState
      v-if="searchMissing"
      state="off"
      headline="Point search not available yet"
      sentence="The catalog search read isn't connected to this console. Enter a point id above to plot it."
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
          <span class="font-mono text-sm text-readout normal-case">{{ point.id }}</span>
          <span class="text-md text-text-3"
            >{{ point.description ?? point.name }}{{ point.unit ? ` · ${point.unit}` : "" }}</span
          >
        </button>
      </li>
    </ul>
  </ApPanel>
</template>
