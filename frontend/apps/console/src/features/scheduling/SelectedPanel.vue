<script setup lang="ts">
import { computed, ref } from "vue";
import type { RemoteState } from "@/api";
import { ApButton, ApEmptyState, ApKeyValue, ApPanel, ApTag, formatDuration } from "@/ui";
import AlternativesList from "./AlternativesList.vue";
import StationIssues from "./StationIssues.vue";
import type { StationHits } from "./unavailable.ts";
import { stationCode, stationName, type Alternatives, type PlanDetail } from "./api.ts";
import { craftLabel, type SpacecraftName } from "./names.ts";
import { useArmedRefocus } from "./useArmedRefocus.ts";

/**
 * D · Selected: a drafted pass (Remove) or another window (Add), then the focused spacecraft's
 * other windows. Values come from the provider; Cadence derives nothing (DECISIONS #4).
 */
const props = defineProps<{
  plan: PlanDetail;
  selected: string | null;
  focused: string | null;
  alternatives: RemoteState<Alternatives>;
  nameOf: (id: string | null) => SpacecraftName | null;
  editable: boolean;
  busy: boolean;
  hits: StationHits;
}>();
const emit = defineEmits<{
  add: [id: string];
  remove: [id: string];
  select: [id: string];
  focus: [spacecraftId: string];
  retry: [];
}>();

const drafted = computed(
  () => props.plan.passes.find((p) => p.snapshot_id === props.selected) ?? null,
);
const other = computed(() => {
  const a = props.alternatives;
  return a.status === "ready"
    ? (a.value.alternatives.find((x) => x.snapshot_id === props.selected) ?? null)
    : null;
});
/**
 * #244 (A5): Remove ↔ Add swap in place once the edit lands (the selection stays). After the
 * person's own click, focus goes to the replacement if it was lost (fe-ops on #590: armed only by
 * that click, never by a background refetch).
 */
const actions = ref<HTMLElement | null>(null);
const swapFocus = useArmedRefocus(
  () => (drafted.value ? "drafted" : other.value ? "other" : null),
  () => actions.value?.querySelector<HTMLElement>("button") ?? null,
);
function act(kind: "add" | "remove", snapshotId: string) {
  swapFocus.arm();
  if (kind === "add") emit("add", snapshotId);
  else emit("remove", snapshotId);
}
const pass = computed(
  () =>
    drafted.value ??
    (other.value ? { ...other.value, spacecraft_id: props.focused, locked: false } : null),
);
const items = computed(() => {
  const p = pass.value;
  if (!p) return [];
  return [
    {
      key: "window",
      label: "Window",
      value: `${p.starts_at.slice(0, 16).replace("T", " ")}–${p.ends_at.slice(11, 16)}Z`,
      mono: true,
    },
    {
      key: "length",
      label: "Length",
      value: formatDuration((Date.parse(p.ends_at) - Date.parse(p.starts_at)) / 1000),
    },
    {
      key: "station",
      label: "Station",
      value: p.station ? `${stationCode(p.station)} · ${stationName(p.station)}` : "Not reported",
      mono: true,
    },
    {
      key: "source",
      label: "Source",
      value: p.synthetic ? "SIMULATOR · SYNTHETIC WINDOW" : "PROVIDER WINDOW",
      mono: true,
    },
    {
      key: "status",
      label: "In plan",
      value: drafted.value ? (p.locked ? "Yes, committed" : "Yes") : "No",
    },
  ];
});
</script>

<template>
  <ApPanel index="D" title="Selected" pane>
    <StationIssues
      :plan="plan"
      :hits="hits"
      :name-of="nameOf"
      :editable="editable"
      :busy="busy"
      @remove="emit('remove', $event)"
      @focus="emit('focus', $event)"
    />
    <template v-if="pass">
      <div class="mb-3 flex flex-wrap items-center gap-2.5">
        <span class="font-mono text-base font-semibold">{{
          craftLabel(nameOf(pass.spacecraft_id))
        }}</span>
        <ApTag v-if="pass.synthetic" state="stale" label="Synthetic" />
      </div>
      <ApKeyValue :items="items" />
      <p class="m-0 mt-3 text-md text-text-3">
        Provider-supplied. Cadence doesn't compute passes yet.
      </p>
      <div v-if="editable" ref="actions" class="mt-3">
        <ApButton
          v-if="drafted && !drafted.locked"
          size="compact"
          :disabled="busy"
          disabled-reason="Working…"
          @click="act('remove', drafted.snapshot_id)"
          >Remove pass</ApButton
        >
        <ApButton
          v-else-if="other"
          size="compact"
          variant="primary"
          :disabled="busy"
          disabled-reason="Working…"
          @click="act('add', other.snapshot_id)"
          >Add pass</ApButton
        >
      </div>
    </template>
    <ApEmptyState
      v-else
      headline="Nothing selected"
      sentence="Click a pass on the Gantt, or a spacecraft in Demand to see its other windows."
    />
    <AlternativesList
      v-if="focused"
      :state="alternatives"
      :editable="editable"
      :busy="busy"
      :name="nameOf(focused)?.name ?? focused"
      @add="emit('add', $event)"
      @select="emit('select', $event)"
      @retry="emit('retry')"
    />
  </ApPanel>
</template>
