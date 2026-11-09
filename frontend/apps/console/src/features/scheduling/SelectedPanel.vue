<script setup lang="ts">
import { computed } from "vue";
import { ApEmptyState, ApKeyValue, ApPanel, ApTag, formatDuration } from "@/ui";
import type { PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";

/** D · Selected pass. Values come from the provider; Cadence derives nothing (DECISIONS #4). */
const props = defineProps<{
  plan: PlanDetail;
  selected: string | null;
  nameOf: (id: string | null) => SpacecraftName | null;
}>();

const pass = computed(
  () => props.plan.passes.find((p) => p.snapshot_id === props.selected) ?? null,
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
    { key: "station", label: "Station", value: p.station ?? "Not reported", mono: true },
    {
      key: "source",
      label: "Source",
      value: p.synthetic ? "SIMULATOR · SYNTHETIC WINDOW" : "PROVIDER WINDOW",
      mono: true,
    },
    { key: "locked", label: "Locked", value: p.locked ? "Yes, committed" : "No" },
  ];
});
</script>

<template>
  <ApPanel index="D" title="Selected" pane>
    <template v-if="pass">
      <div class="mb-3 flex flex-wrap items-center gap-2.5">
        <span class="font-mono text-base font-semibold">{{
          nameOf(pass.spacecraft_id)?.name ?? pass.spacecraft_id
        }}</span>
        <ApTag v-if="pass.synthetic" state="stale" label="Synthetic" />
      </div>
      <ApKeyValue :items="items" />
      <p class="m-0 mt-3 text-md text-text-3">
        Provider-supplied. Cadence doesn't compute passes yet.
      </p>
    </template>
    <ApEmptyState
      v-else
      headline="Nothing selected"
      sentence="Click a pass on the Gantt, or a spacecraft in Demand to focus it."
    />
  </ApPanel>
</template>
