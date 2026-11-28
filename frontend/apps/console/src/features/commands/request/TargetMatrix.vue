<script setup lang="ts">
import { computed } from "vue";
import { targetVerifyTime } from "../groups/verifyTimes.ts";
import { layoutMatrix, type FleetSpacecraft } from "@/features/fleet/index.ts";
import type { Group, GroupTarget } from "../groups/show.ts";
import { LOOK_WORDS, legendLooks, targetLook, type CellLook } from "../groups/matrix.ts";
import { targetStageWord } from "../groups/expiry.ts";

/**
 * U1 Targets matrix (CommandFlow C3): one cell per target in plane rows (by slot), its stage as a
 * look, with a legend. Pointer-only and hidden from assistive tech; the target list under it is
 * the accessible path, and a summary sentence says the counts.
 *
 * #795: it draws the targets the list has loaded (`targets`), so the cells and the rows under
 * them always agree; a group of thousands fills in as the list pages.
 */
const props = defineProps<{
  group: Group;
  targets: readonly GroupTarget[];
  fleet: readonly FleetSpacecraft[];
}>();
const stageOf = computed(
  () => new Map(props.targets.map((t) => [t.spacecraft_id, t.stage] as const)),
);
const layout = computed(() => layoutMatrix(props.fleet.filter((sc) => stageOf.value.has(sc.id))));
const CLASS: Readonly<Record<CellLook, string>> = {
  verified: "bg-nominal-dim",
  executed: "bg-text-3",
  radiating: "bg-readout ring-1 ring-readout ring-offset-1 ring-offset-panel",
  queued: "border border-text-3",
  no_ack: "bg-caution",
  failed: "bg-crit ring-1 ring-crit ring-offset-1 ring-offset-panel",
  excluded: "border border-dashed border-text-4",
  expired: "border border-dashed border-text-3",
  unverifiable: "border border-stale bg-stale-deep",
};
const targetOf = computed(() => new Map(props.targets.map((t) => [t.spacecraft_id, t])));
const lookOf = (sc: FleetSpacecraft | null) => {
  const t = sc ? targetOf.value.get(sc.id) : undefined;
  return t ? targetLook(t) : null;
};
const legend = computed(() => legendLooks(props.targets));
/** The cell's title: name · stage (an expired one reads 'Expired') · verify time. */
const titleOf = (sc: FleetSpacecraft) => {
  const t = targetOf.value.get(sc.id);
  return [sc.name, t ? targetStageWord(t, props.group) : null, targetVerifyTime(t)]
    .filter(Boolean)
    .join(" · ");
};
const summary = computed(() =>
  legend.value
    .map((l) => {
      const n = props.targets.filter((t) => targetLook(t) === l).length;
      return `${n} ${LOOK_WORDS[l].toLowerCase()}`;
    })
    .join(", "),
);
</script>

<template>
  <div v-if="layout.rows.length" class="flex flex-col gap-2 px-4 py-3">
    <p class="sr-only">Targets shown by stage: {{ summary }}.</p>
    <div aria-hidden="true" class="flex flex-col gap-[3px] overflow-x-auto">
      <div v-for="row in layout.rows" :key="row.key" class="flex items-center gap-2">
        <span class="w-9 flex-none font-mono text-[10px] text-text-4">{{ row.label }}</span>
        <span class="flex gap-[3px]">
          <span
            v-for="(sc, i) in row.cells"
            :key="sc?.id ?? `empty-${i}`"
            class="size-3 flex-none"
            :class="lookOf(sc) ? CLASS[lookOf(sc) ?? 'queued'] : 'bg-cell-empty'"
            :title="sc ? titleOf(sc) : undefined"
          />
        </span>
      </div>
    </div>
    <ul aria-hidden="true" class="m-0 flex list-none flex-wrap gap-x-4 gap-y-1 p-0">
      <li v-for="l in legend" :key="l" class="flex items-center gap-1.5 text-xs text-text-3">
        <span class="size-3 flex-none" :class="CLASS[l]" />{{ LOOK_WORDS[l] }}
      </li>
    </ul>
  </div>
</template>
