<script setup lang="ts">
import { spacecraftIdParam } from "@/api/index.ts";
import { computed, onBeforeUnmount, onMounted, shallowRef, useTemplateRef } from "vue";
import { RouterLink } from "vue-router";
import { formatDuration, plural, ApStatusMark } from "@/ui";
import { useCoarseNow } from "./coarseClock.ts";
import type { FleetSpacecraft } from "./api.ts";
import { fitMatrix, fleetOpState, fleetStateWord, layoutMatrix, splitRows } from "./matrix.ts";
import PlanePicker from "./PlanePicker.vue";

/**
 * One cell per spacecraft, rows = planes (design-language §7 ApFleetMatrix, U8). The cell grid
 * (including row labels) is pointer-only and hidden from assistive tech; the summary sentence,
 * the plane picker and the Fleet table are the accessible path (qa issue #5). With `fitHeight`
 * the cells shrink to the box's height (8–16px) and scroll below 8px.
 */
const props = defineProps<{
  spacecraft: readonly FleetSpacecraft[];
  selectedPlane: number | null;
  fitHeight?: boolean;
  /** Show the "View as table" link to the Fleet screen. */
  tableLink?: boolean;
  /** Hide the footer plane picker when the owner already offers one (Fleet filter row). */
  noPlanePicker?: boolean;
  /**
   * `selection` (Compose targeting): matching cells are filled white, the rest empty; health
   * colors are off so "selected" never reads as a state (ux Compose review 3).
   */
  mode?: "health" | "selection";
  /** Filter: non-matching cells are drawn at 25% opacity, never hidden (fleet first). */
  matches?: ((sc: FleetSpacecraft) => boolean) | undefined;
}>();
const emit = defineEmits<{ open: [sc: FleetSpacecraft]; selectPlane: [plane: number | null] }>();

const area = useTemplateRef<HTMLDivElement>("area");
const box = shallowRef({ width: 0, height: 0 });
let observer: ResizeObserver | null = null;
onMounted(() => {
  const el = area.value;
  if (!el) return;
  observer = new ResizeObserver(() => {
    box.value = { width: el.clientWidth, height: el.clientHeight };
  });
  observer.observe(el);
});
onBeforeUnmount(() => observer?.disconnect());

/** §2: ages move on the fleet's 10 s tick, not the 1 Hz clock. */
const now = useCoarseNow();
const layout = computed(() => layoutMatrix(props.spacecraft));
const planes = computed(() =>
  layout.value.rows.flatMap((row) => (row.plane === null ? [] : [row.plane])),
);
const fit = computed(() =>
  fitMatrix(
    box.value.width,
    props.fitHeight ? box.value.height : null,
    layout.value.rows.length,
    layout.value.columns,
  ),
);
const blocks = computed(() => splitRows(layout.value.rows, fit.value.blocks));
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
  if (props.mode === "selection")
    return [props.matches?.(sc) ? "bg-readout" : "bg-cell-empty", "cursor-pointer"];
  const dim = props.matches && !props.matches(sc) ? "opacity-25" : "";
  // In contact: the white ring replaces any other ring (a crit cell keeps its red fill).
  if (sc.in_contact === true)
    return [CELL[sc.state].replace(/outline\S*/g, "").trim(), LIVE_RING, "cursor-pointer", dim];
  return [CELL[sc.state], "cursor-pointer", dim];
}

function target(event: Event): FleetSpacecraft | null {
  const el = event.target instanceof Element ? event.target.closest("[data-sc]") : null;
  const id = spacecraftIdParam(el?.getAttribute("data-sc") ?? undefined);
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
    const age = (now.value - Date.parse(sc.last_received_at)) / 1000;
    parts.push(`last TLM ${formatDuration(age)}`);
  }
  return { state: fleetOpState(sc.state), text: parts.join(" · ") };
});
</script>

<template>
  <div class="flex flex-col gap-2" :class="fitHeight ? 'h-full min-h-0' : ''">
    <p class="sr-only">{{ summary }}</p>
    <div
      ref="area"
      aria-hidden="true"
      class="flex min-h-0 flex-wrap content-start gap-x-4 gap-y-[2px]"
      :class="fitHeight ? 'flex-1 overflow-auto' : ''"
      @mouseleave="hovered = null"
    >
      <div v-for="(block, b) in blocks" :key="b" class="flex flex-col gap-[2px]">
        <div v-for="row in block" :key="row.key" class="flex items-center gap-2">
          <span
            class="w-9 flex-none font-mono text-[10px] leading-none"
            :class="[
              row.plane !== null && row.plane === selectedPlane ? 'text-readout' : 'text-text-4',
              row.plane !== null ? 'cursor-pointer hover:text-readout' : '',
            ]"
            @click="
              row.plane !== null &&
              emit('selectPlane', row.plane === selectedPlane ? null : row.plane)
            "
            >{{ row.label }}</span
          >
          <div
            class="grid flex-none gap-[2px]"
            :style="{ gridTemplateColumns: `repeat(${layout.columns}, ${fit.cell}px)` }"
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
    </div>
    <div class="flex flex-none flex-wrap items-center gap-3">
      <PlanePicker
        v-if="planes.length > 0 && !noPlanePicker"
        :planes="planes"
        :selected-plane="selectedPlane"
        @select-plane="emit('selectPlane', $event)"
      />
      <p
        aria-hidden="true"
        class="m-0 flex min-w-0 flex-1 items-center gap-2 font-mono text-xs text-text-3"
      >
        <template v-if="inspector"
          ><ApStatusMark :state="inspector.state" />{{ inspector.text }}</template
        >
      </p>
      <RouterLink
        v-if="tableLink"
        :to="{ name: 'ops.fleet' }"
        class="max-md:hit-44 font-mono text-xs text-text-3 uppercase no-underline hover:text-readout"
        >View as table →</RouterLink
      >
    </div>
  </div>
</template>
