<script setup lang="ts">
import { computed } from "vue";
import { ApGantt, ApPanel, formatCount, useNow, type GanttBar, type GanttRow } from "@/ui";
import type { RemoteState } from "@/api";
import type { Alternatives, PlanDetail } from "./api.ts";
import type { SpacecraftName } from "./names.ts";

/** B · Draft by station: the plan's passes; the focused spacecraft ringed, conflicts dashed caution. */
const props = defineProps<{
  plan: PlanDetail;
  day: string;
  nameOf: (id: string | null) => SpacecraftName | null;
  focused: string | null;
  selected: string | null;
  /** The focused spacecraft's other windows, drawn dashed (clash = dashed caution). */
  alternatives?: RemoteState<Alternatives> | undefined;
}>();
defineEmits<{ select: [snapshotId: string] }>();
const now = useNow();

const window = computed(() => {
  const from = Date.parse(`${props.day}T00:00:00Z`);
  return { from, to: from + 86_400_000 };
});
const clashing = computed(() => new Set(props.plan.conflicts.flatMap((c) => c.snapshot_ids)));
const others = computed(() =>
  props.alternatives?.status === "ready" ? props.alternatives.value.alternatives : [],
);
const rows = computed<GanttRow[]>(() =>
  [...new Set([...props.plan.passes, ...others.value].map((p) => p.station ?? "?"))]
    .sort()
    .map((s) => ({ id: s, label: s })),
);
const windowBars = computed<GanttBar[]>(() =>
  others.value.map((a) => ({
    id: a.snapshot_id,
    rowId: a.station ?? "?",
    from: Date.parse(a.starts_at),
    to: Date.parse(a.ends_at),
    kind: a.effect.clashes_with.length > 0 ? "clash" : "window",
    description: `Other window · ${a.station ?? "unknown station"} · ${a.starts_at.slice(11, 16)}–${a.ends_at.slice(11, 16)}Z${a.effect.clashes_with.length > 0 ? " · clashes" : ""}`,
  })),
);
const draftedBars = computed<GanttBar[]>(() =>
  props.plan.passes.map((p) => {
    const sc = props.nameOf(p.spacecraft_id);
    const who = sc ? `${sc.name} (SCID ${sc.scid})` : (p.spacecraft_id ?? "unknown spacecraft");
    return {
      id: p.snapshot_id,
      rowId: p.station ?? "?",
      from: Date.parse(p.starts_at),
      to: Date.parse(p.ends_at),
      kind: clashing.value.has(p.snapshot_id)
        ? "clash"
        : p.spacecraft_id === props.focused
          ? "focused"
          : "own",
      label: sc ? String(sc.scid) : undefined,
      description: `${who} · ${p.station ?? "unknown station"} · ${p.starts_at.slice(11, 16)}–${p.ends_at.slice(11, 16)}Z${clashing.value.has(p.snapshot_id) ? " · conflict" : ""}`,
    };
  }),
);
const bars = computed(() => [...draftedBars.value, ...windowBars.value]);
</script>

<template>
  <ApPanel
    index="B"
    title="Draft · by station"
    :meta="`${formatCount(plan.passes.length)} passes · ${rows.length} stations · 00–24Z`"
    pane
  >
    <ApGantt
      label="Drafted passes by station"
      :rows="rows"
      :bars="bars"
      :window="window"
      :now="now.getTime()"
      :selected="selected"
      @select="$emit('select', $event)"
    />
  </ApPanel>
</template>
