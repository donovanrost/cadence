<script setup lang="ts">
import { computed, shallowRef } from "vue";
import { formatDuration, plural, useNow, ApStatusMark } from "@/ui";
import type { FleetSpacecraft } from "./api.ts";
import { fleetOpState, fleetStateWord, layoutMatrix } from "./matrix.ts";

/**
 * One cell per spacecraft, rows = planes (design-language §7 ApFleetMatrix, U8). Cells are
 * pointer-only and hidden from assistive tech; the plane buttons, the summary sentence and the
 * Fleet table are the accessible path. Always pair with a stat strip carrying the counts.
 */
const props = defineProps<{
  spacecraft: readonly FleetSpacecraft[];
  selectedPlane: number | null;
}>();
const emit = defineEmits<{ open: [sc: FleetSpacecraft]; selectPlane: [plane: number | null] }>();

const now = useNow();
const layout = computed(() => layoutMatrix(props.spacecraft));
const byId = computed(() => new Map(props.spacecraft.map((sc) => [sc.id, sc])));
const hovered = shallowRef<FleetSpacecraft | null>(null);

const summary = computed(() => {
  const crit = props.spacecraft.filter((sc) => sc.state === "critical").map((sc) => sc.name);
  const rows = layout.value.mode === "planes" ? plural(layout.value.rows.length, "row") : "";
  const critText = crit.length ? `Critical: ${crit.slice(0, 5).join(", ")}.` : "None critical.";
  return `Fleet matrix of ${plural(props.spacecraft.length, "spacecraft", "spacecraft")}${rows ? `, ${rows} by plane` : ""}. ${critText}`;
});

const LIVE_RING = "outline outline-1 outline-offset-[1.5px] outline-action";

/** Full class strings only: Tailwind finds candidates by scanning source text. */
const CELL: Readonly<Record<FleetSpacecraft["state"], string>> = {
  critical: "bg-crit outline outline-1 outline-offset-[1.5px] outline-crit",
  caution: "bg-caution",
  stale: "border border-stale bg-stale-deep bg-[image:var(--apogee-hatch-stale-cell)]",
  nominal: "bg-nominal-bulk",
  never_heard: "border border-dashed border-off",
};

function cellClass(sc: FleetSpacecraft | null): readonly string[] {
  if (sc === null) return ["bg-cell-empty"];
  // In contact: the white ring replaces any other ring (a crit cell keeps its red fill).
  if (sc.in_contact === true)
    return [CELL[sc.state].replace(/outline\S*/g, "").trim(), LIVE_RING, "cursor-pointer"];
  return [CELL[sc.state], "cursor-pointer"];
}

function target(event: Event): FleetSpacecraft | null {
  const el = event.target instanceof Element ? event.target.closest("[data-sc]") : null;
  const id = el?.getAttribute("data-sc");
  return id ? (byId.value.get(id) ?? null) : null;
}

function onClick(event: MouseEvent) {
  const sc = target(event);
  if (sc) emit("open", sc);
}

const inspector = computed(() => {
  const sc = hovered.value;
  if (!sc) return null;
  const parts = [sc.name, `SCID ${sc.scid}`, fleetStateWord(sc.state)];
  if (sc.worst_point) parts.push(sc.worst_point.point_name);
  if (sc.last_received_at) {
    const age = (now.value.getTime() - Date.parse(sc.last_received_at)) / 1000;
    parts.push(`last TLM ${formatDuration(age)}`);
  }
  return { state: fleetOpState(sc.state), text: parts.join(" · ") };
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <p class="sr-only">{{ summary }}</p>
    <div class="flex flex-col gap-[2px]" @mouseleave="hovered = null">
      <div v-for="row in layout.rows" :key="row.key" class="flex items-center gap-2">
        <button
          v-if="row.plane !== null"
          type="button"
          class="w-9 flex-none cursor-pointer text-left font-mono text-[10px] leading-none hover:text-readout"
          :class="row.plane === selectedPlane ? 'text-readout' : 'text-text-4'"
          :aria-pressed="row.plane === selectedPlane"
          :aria-label="`Plane ${row.plane}`"
          @click="emit('selectPlane', row.plane === selectedPlane ? null : row.plane)"
        >
          {{ row.label }}
        </button>
        <span v-else class="w-9 flex-none font-mono text-[10px] leading-none text-text-4">{{
          row.label
        }}</span>
        <div
          aria-hidden="true"
          class="grid min-w-0 flex-1 gap-[2px]"
          :style="{
            gridTemplateColumns: `repeat(${layout.columns}, minmax(0, 1fr))`,
            maxWidth: `${layout.columns * 18}px`,
          }"
          @click="onClick"
          @mouseover="hovered = target($event)"
        >
          <span
            v-for="(sc, i) in row.cells"
            :key="sc?.id ?? `empty-${i}`"
            :data-sc="sc?.id"
            class="box-border aspect-square"
            :class="cellClass(sc)"
          />
        </div>
      </div>
    </div>
    <p aria-hidden="true" class="m-0 flex h-4 items-center gap-2 font-mono text-xs text-text-3">
      <template v-if="inspector"
        ><ApStatusMark :state="inspector.state" />{{ inspector.text }}</template
      >
    </p>
  </div>
</template>
