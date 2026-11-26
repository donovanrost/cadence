<script setup lang="ts">
import { computed } from "vue";
import {
  ApGantt,
  ApPanel,
  formatCount,
  useNow,
  type GanttBand,
  type GanttBar,
  type GanttRow,
} from "@/ui";
import type { RemoteState } from "@/api";
import {
  distinctWindows,
  type Availability,
  stationCode,
  stationKey,
  stationName,
  type Alternatives,
  type PlanDetail,
  type StationRef,
} from "./api.ts";
import { bookingLook } from "./booking-state.ts";
import type { SpacecraftName } from "./names.ts";
import { overlapWords, type ListenerOverlap } from "@/features/contacts/listenerOverlap.ts";

/** B · Draft by station: the plan's passes; the focused spacecraft ringed, conflicts dashed caution. */
const props = defineProps<{
  plan: PlanDetail;
  day: string;
  /** Overrides the 00–24Z day (repair horizons). */
  span?: { from: number; to: number } | undefined;
  /** Panel heading and index (B1 live plan / B2 proposal). */
  title?: string | undefined;
  index?: string | undefined;
  /** S7 station availability: windows become bands, down/degraded stations tint their row. */
  availability?: RemoteState<Availability> | undefined;
  /** Superseded draft: dim the marks (not the text, which stays at full contrast). */
  muted?: boolean | undefined;
  nameOf: (id: string | null) => SpacecraftName | null;
  focused: string | null;
  selected: string | null;
  /** The focused spacecraft's other windows, drawn dashed (clash = dashed caution). */
  alternatives?: RemoteState<Alternatives> | undefined;
}>();
defineEmits<{ select: [snapshotId: string] }>();
const now = useNow();

const window = computed(() => {
  if (props.span) return props.span;
  const from = Date.parse(`${props.day}T00:00:00Z`);
  return { from, to: from + 86_400_000 };
});
/** U58 (b), #361: the pass that may lose its start to a one-connection listener (this or either). */
const losesStart = (p: Readonly<{ listener_overlap?: ListenerOverlap | null | undefined }>) =>
  overlapWords(p.listener_overlap)?.tag === true;
const clashing = computed(() => new Set(props.plan.conflicts.flatMap((c) => c.snapshot_ids)));
const down = computed(
  () =>
    new Set(
      props.plan.conflicts
        .filter((c) => c.code === "station_unavailable")
        .flatMap((c) => c.snapshot_ids),
    ),
);
const risky = computed(() => new Set(props.plan.at_risk.flatMap((r) => r.snapshot_ids)));
/** U30: placed, provider silent past its window; stale-hatched. Value: when it was sent. */
const unconfirmed = computed(
  () => new Map(props.plan.unconfirmed?.passes.map((p) => [p.snapshot_id, p.sent_at]) ?? []),
);
const others = computed(() =>
  props.alternatives?.status === "ready"
    ? distinctWindows(props.alternatives.value.alternatives)
    : [],
);
const rows = computed<GanttRow[]>(() => {
  const byKey = new Map<string, StationRef>();
  for (const p of [...props.plan.passes, ...others.value])
    byKey.set(stationKey(p.station), p.station);
  return [...byKey.entries()]
    .map(([id, st]) => ({
      id,
      label: stationCode(st),
      name: stationName(st),
      degraded: stationState.value.get(id) !== undefined && stationState.value.get(id) !== "up",
    }))
    .sort((a, b) => a.label.localeCompare(b.label));
});
const windowBars = computed<GanttBar[]>(() =>
  others.value.map((a) => ({
    id: a.snapshot_id,
    rowId: stationKey(a.station),
    from: Date.parse(a.starts_at),
    to: Date.parse(a.ends_at),
    kind: a.effect.clashes_with.length > 0 ? "clash" : "window",
    description: `Other window · ${stationName(a.station)} · ${a.starts_at.slice(11, 16)}–${a.ends_at.slice(11, 16)}Z${a.effect.clashes_with.length > 0 ? " · clashes" : ""}`,
  })),
);
const draftedBars = computed<GanttBar[]>(() =>
  props.plan.passes.map((p) => {
    const sc = props.nameOf(p.spacecraft_id);
    const who = sc
      ? sc.scid === null
        ? sc.name
        : `${sc.name} (SCID ${sc.scid})`
      : (p.spacecraft_id ?? "unknown spacecraft");
    // Executing: the pass's own booking wins (api 8e), except the U30 unconfirmed hatch.
    const booked = props.muted ? null : bookingLook(p.booking);
    return {
      id: p.snapshot_id,
      rowId: stationKey(p.station),
      from: Date.parse(p.starts_at),
      to: Date.parse(p.ends_at),
      kind: props.muted
        ? "done"
        : unconfirmed.value.has(p.snapshot_id)
          ? "unconfirmed"
          : booked
            ? booked.kind
            : clashing.value.has(p.snapshot_id) || down.value.has(p.snapshot_id)
              ? "clash"
              : risky.value.has(p.snapshot_id)
                ? "risk"
                : p.spacecraft_id === props.focused
                  ? "focused"
                  : "own",
      label: sc && sc.scid !== null ? String(sc.scid) : undefined,
      // U58 (b), #361: the pass that may lose its start gets U45's caution mark, said in words too.
      ...(losesStart(p) ? { attention: "caution" as const } : {}),
      description: `${who} · ${stationName(p.station)} · ${p.starts_at.slice(11, 16)}–${p.ends_at.slice(11, 16)}Z${clashing.value.has(p.snapshot_id) ? " · conflict" : ""}${down.value.has(p.snapshot_id) ? " · station down" : risky.value.has(p.snapshot_id) ? " · station degraded, may lose data" : ""}${unconfirmed.value.has(p.snapshot_id) ? ` · UNCONFIRMED · sent ${unconfirmed.value.get(p.snapshot_id)?.slice(11, 16) ?? "?"}Z` : booked ? ` · ${booked.word}${p.booking?.reason && p.booking.reason !== "sending" ? `: ${p.booking.reason.replaceAll("_", " ")}` : ""}` : ""}${losesStart(p) ? " · listener overlap" : ""}`,
    };
  }),
);
const bars = computed(() => [...draftedBars.value, ...windowBars.value]);
const rangeText = computed(() =>
  props.span
    ? `${new Date(props.span.from).toISOString().slice(11, 16)}–${new Date(props.span.to).toISOString().slice(11, 16)}Z`
    : "00–24Z",
);
const stations = computed(() =>
  props.availability?.status === "ready" ? props.availability.value.stations : [],
);
// Looked up by stationKey (the id, else the provider's ref), which is text.
const stationState = computed(
  () => new Map<string, string>(stations.value.map((st) => [st.ground_station_id, st.state])),
);
const bands = computed<GanttBand[]>(() =>
  stations.value.flatMap((st) =>
    st.windows
      .filter((w) => w.cleared_at === null)
      .map((w) => ({
        rowId: w.ground_station_id,
        from: Date.parse(w.from),
        to: w.to ? Date.parse(w.to) : window.value.to,
        kind: w.kind,
        label: `${w.kind[0]?.toUpperCase() ?? ""}${w.kind.slice(1)}${w.reason ? `: ${w.reason}` : ""}${w.to ? "" : " · no end reported"}`,
      })),
  ),
);
</script>

<template>
  <ApPanel
    :index="index ?? 'B'"
    :title="title ?? 'Draft · by station'"
    :meta="`${formatCount(plan.passes.length)} passes · ${rows.length} stations · ${rangeText}`"
    pane
  >
    <ApGantt
      label="Drafted passes by station"
      :label-width="rows.every((r) => r.label.length <= 8) ? 88 : 150"
      :rows="rows"
      :bars="bars"
      :bands="bands"
      :window="window"
      :now="now.getTime()"
      :selected="selected"
      @select="$emit('select', $event)"
    />
  </ApPanel>
</template>
