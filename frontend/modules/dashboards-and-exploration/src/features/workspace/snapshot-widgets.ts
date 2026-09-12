import type { WidgetPointPresentation } from "./WidgetPoint.contracts";
import type { WidgetRowsPresentation } from "./WidgetRows.contracts";
import type { DashboardWidgetPresentation } from "./DashboardWidget.contracts";
import type {
  WorkspaceField,
  WorkspaceFrame,
  WorkspacePlacement,
  WorkspaceSnapshot,
} from "./contracts";
import { snapshotSeries } from "./snapshot-series.ts";

type Point = WidgetPointPresentation;
type Rows = WidgetRowsPresentation;
type Body = DashboardWidgetPresentation["body"];
type Cell = WorkspaceField["values"][number];
type Row = Record<string, Cell>;
export const muted = "text-xs font-mono text-base-content/60";
const tones = {
  red: "bg-error/15 text-error",
  yellow: "bg-warning/15 text-warning",
  blue: "bg-info/15 text-info",
  green: "bg-success/15 text-success",
  no_data: "bg-base-300 text-base-content/60",
};
function healthState(row: Row): keyof typeof tones {
  const state = row.worst_state === null ? "no_data" : row.worst_state;
  if (
    state === "red" ||
    state === "yellow" ||
    state === "blue" ||
    state === "green" ||
    state === "no_data"
  )
    return state;
  throw Error("Unknown health state");
}
function placementWidget(placement: WorkspacePlacement) {
  if (!placement.widget) throw Error("Missing widget definition");
  return placement.widget;
}
export const label = (value: Cell | undefined): string =>
  value == null ? "No data" : String(value);
export const timestamp = (value: Cell | undefined): string => {
  if (typeof value !== "number") return "Time unavailable";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "Time unavailable" : date.toISOString();
};
export function frameRows(frame: WorkspaceFrame): Row[] {
  return Array.from({ length: frame.fields[0]?.values.length ?? 0 }, (_, index) =>
    Object.fromEntries(
      frame.fields.map((field) => {
        const value = field.values[index];
        if (value === undefined) throw Error("Incomplete frame row");
        return [field.name, value];
      }),
    ),
  );
}
const format = (value: Cell | undefined, field: WorkspaceField, precision: number) =>
  field.kind === "time"
    ? timestamp(value)
    : typeof value === "number"
      ? value.toFixed(precision)
      : label(value);

function point(
  placement: WorkspacePlacement,
  snapshot: WorkspaceSnapshot,
  id: string,
  group: string,
): Point {
  const widget = placementWidget(placement);
  const primary = placement.frames.filter((frame) => frame.role === "primary");
  if (widget.type === "time_series") {
    const plotted = placement.frames.filter((f) => f.role === "primary" || f.role === "compare");
    if (new Set(plotted.map((f) => f.time_axis)).size !== 1)
      throw Error("Incompatible chart time axes");
    const series = snapshotSeries(primary, placement.id);
    const compare = snapshotSeries(
      placement.frames.filter((f) => f.role === "compare"),
      placement.id,
    );
    return {
      kind: "time_series",
      component_id: `${id}-point`,
      host: { class: "contents" },
      stage: { class: "h-full min-h-40 flex flex-col", attrs: {} },
      data_management: null,
      chart: {
        component_id: `${id}-chart-host`,
        class: "flex h-full min-h-40",
        props: {
          chart_id: `${id}-chart`,
          widget_id: placement.authored_id,
          placement_id: placement.id,
          correlation_group: group,
          ...(widget.options.show_min_max_band === undefined
            ? {}
            : { show_min_max_band: widget.options.show_min_max_band }),
          ...(widget.options.legend_mode === undefined
            ? {}
            : { legend_mode: widget.options.legend_mode }),
          ...(widget.options.line_width === undefined
            ? {}
            : { line_width: widget.options.line_width }),
          ...(widget.options.fill_opacity === undefined
            ? {}
            : { fill_opacity: widget.options.fill_opacity }),
          ...(widget.options.span_gaps === undefined
            ? {}
            : { span_gaps: widget.options.span_gaps }),
          ...(widget.options.show_points === undefined
            ? {}
            : { show_points: widget.options.show_points }),
          ...(widget.options.axis_mode === undefined
            ? {}
            : { axis_mode: widget.options.axis_mode }),
          ...(widget.options.shared_tooltip === undefined
            ? {}
            : { shared_tooltip: widget.options.shared_tooltip }),
          window_seconds: snapshot.context.window_seconds ?? widget.options.window_seconds,
          label: widget.title,
          backfill: { series },
          compare_backfill: { series: compare },
          time_mode:
            snapshot.context.time_mode === "live" ? "snapshot" : snapshot.context.time_mode,
          time_axis: primary[0]?.time_axis ?? snapshot.context.time_axis,
          time_from: snapshot.context.from ?? "",
          time_to: snapshot.context.to ?? "",
          data_realm: snapshot.context.realm,
          data_view: snapshot.context.data_view,
          engine_backed: true,
          annotations: placement.annotations.map((a) => ({
            annotation_id: a.id,
            title: a.title,
            severity: a.severity,
            geometry: a.kind,
            starts_at_ms: a.starts_at_ms,
            ends_at_ms: a.ends_at_ms,
            ...(a.kind === "point" ? { timestamp_ms: a.starts_at_ms } : {}),
          })),
        },
      },
    };
  }
  if (widget.type === "constellation_health") {
    const entries = primary.flatMap((frame) => {
      if (
        frame.shape !== "matrix" ||
        !frame.fields.some((f) => f.name === "spacecraft_id") ||
        !frame.fields.some((f) => f.name === "worst_state")
      )
        throw Error("Invalid health frame");
      return frameRows(frame);
    });
    const ids = entries.map((row) => row.spacecraft_id);
    if (ids.some((id) => typeof id !== "string" || !id) || new Set(ids).size !== ids.length)
      throw Error("Ambiguous spacecraft health");
    const states = entries.map(healthState);
    return {
      kind: "constellation_health",
      component_id: `${id}-point`,
      host: { class: "contents" },
      badges: {
        class: "flex flex-wrap gap-2 mb-3",
        items: Object.entries(tones).map(([state, tone]) => ({
          class: `inline-flex items-center gap-1.5 rounded px-2 py-1 ${tone}`,
          dot_class: "hidden",
          count: states.filter((s) => s === state).length,
          count_class: "font-mono font-semibold",
          label: state === "no_data" ? "No data" : state,
          label_class: "text-xs capitalize",
        })),
      },
      spacecraft: {
        class: "flex flex-wrap gap-2",
        attrs: {},
        items: entries.map((row) => ({
          key: String(row.spacecraft_id),
          class: `inline-block h-5 w-5 rounded ${tones[healthState(row)]}`,
          attrs: {
            role: "img",
            title: `${row.spacecraft_id}: ${healthState(row)}`,
            "aria-label": `${row.spacecraft_id}: ${healthState(row)}`,
            "data-spacecraft-id": String(row.spacecraft_id),
          },
        })),
      },
    };
  }
  if (primary.length !== 1) throw Error("A value tile requires one resolved value");
  const frame = primary[0];
  if (!frame || !["scalar", "matrix"].includes(frame.shape)) throw Error("Invalid value frame");
  const values =
    frame.shape === "matrix"
      ? frame.fields.filter((f) => f.name === "value")
      : frame.fields.filter((f) => f.kind !== "time");
  const field = values[0];
  if (values.length !== 1 || !field || field.values.length !== 1)
    throw Error("Ambiguous value tile");
  const row = frameRows(frame)[0];
  if (!row) throw Error("Missing value row");
  const unit = field.unit ?? (typeof row.unit === "string" ? row.unit : null);
  const time = frame.fields.find((f) => f.kind === "time");
  return {
    kind: "value_tile",
    component_id: `${id}-point`,
    host: { class: "contents" },
    value: {
      container_class: "flex items-baseline gap-2",
      text: format(field.values[0], field, widget.options.precision),
      class: "text-3xl font-mono tabular-nums",
      attrs: { "data-workspace-value": placement.id },
      unit: unit && widget.options.show_unit !== false ? { text: unit, class: muted } : null,
    },
    timestamp: { text: timestamp(time?.values[0]), class: `mt-2 ${muted}` },
    comparison: null,
  };
}

function table(placement: WorkspacePlacement, id: string): Rows {
  const widget = placementWidget(placement);
  const kind = widget.type;
  if (kind !== "data_table" && kind !== "status_matrix") throw Error("Invalid table widget");
  const primary = placement.frames.filter((f) => f.role === "primary");
  if (primary.some((f) => !["scalar", "matrix", "long"].includes(f.shape)))
    throw Error("Invalid table frame");
  // Field identity includes kind and unit: unlike columns must not be silently merged.
  const columns = Array.from(
    new Map(
      primary.flatMap((f) =>
        f.fields.map(
          (field) => [JSON.stringify([field.name, field.kind, field.unit]), field] as const,
        ),
      ),
    ).entries(),
  );
  return {
    kind,
    component_id: `${id}-rows`,
    root: { class: "table table-xs w-full" },
    head: {
      class: muted,
      row_class: "",
      cells: columns.map(([key, field]) => ({
        key,
        class: "whitespace-nowrap",
        text: field.unit ? `${field.name} (${field.unit})` : field.name,
        text_class: null,
      })),
    },
    rows: primary.flatMap((frame, frameIndex) =>
      frameRows(frame).map((row, rowIndex) => ({
        key: `${frameIndex}-${rowIndex}`,
        class: "hover:bg-base-200/40",
        attrs: {},
        cells: columns.map(([key, field]) => ({
          key,
          class: "font-mono text-xs tabular-nums",
          attrs: {},
          badges: [],
          link_menu: null,
          text: frame.fields.some(
            (f) => f.name === field.name && f.kind === field.kind && f.unit === field.unit,
          )
            ? format(row[field.name], field, placementWidget(placement).options.precision)
            : "—",
        })),
      })),
    ),
  };
}

function timeline(placement: WorkspacePlacement, id: string): Rows {
  const primary = placement.frames.filter((f) => f.role === "primary");
  if (placementWidget(placement).type === "event_timeline") {
    const rows = primary
      .flatMap((frame, frameIndex) => {
        if (!["events", "intervals"].includes(frame.shape)) throw Error("Invalid event frame");
        return frameRows(frame).map((row, index) => {
          const time = row.occurred_at ?? row.time ?? row.starts_at;
          if (typeof time !== "number") throw Error("Missing event time");
          if (
            frame.shape === "intervals" &&
            row.ends_at != null &&
            (typeof row.ends_at !== "number" || row.ends_at < time)
          )
            throw Error("Invalid event interval");
          return { row, time, key: `${frameIndex}-${index}` };
        });
      })
      .sort((a, b) => b.time - a.time);
    return {
      kind: "event_timeline",
      component_id: `${id}-rows`,
      root: { class: "space-y-3" },
      rows: rows.map(({ row, time, key }) => ({
        key,
        class: "flex gap-3",
        attrs: {},
        marker: { container_class: "pt-1.5", class: "block h-2 w-2 rounded-full bg-info" },
        content_class: "min-w-0",
        heading_class: "flex flex-wrap gap-2 items-center",
        category: { class: muted, text: label(row.category ?? row.kind) },
        badges:
          row.severity == null
            ? []
            : [
                {
                  tag: "span" as const,
                  class: "badge badge-xs",
                  attrs: {},
                  text: label(row.severity),
                },
              ],
        time: { class: muted, text: timestamp(time) },
        title: {
          class: "text-sm font-medium break-words",
          attrs: {},
          text: label(row.title ?? row.label ?? row.kind),
        },
        metadata_class: `flex flex-wrap gap-x-3 gap-y-1 ${muted}`,
        metadata:
          row.starts_at !== undefined
            ? [`Ends: ${row.ends_at == null ? "Open interval" : timestamp(row.ends_at)}`]
            : [],
        actions_class: "hidden",
        link_menu: null,
      })),
    };
  }
  return {
    kind: "state_timeline",
    component_id: `${id}-rows`,
    root: { class: "space-y-4" },
    lanes: primary.map((frame, frameIndex) => {
      if (
        !["events", "scalar"].includes(frame.shape) ||
        !frame.fields.some((f) => f.name === "normalized_state")
      )
        throw Error("Invalid state frame");
      const rows = frameRows(frame).sort((a, b) => Number(a.time) - Number(b.time));
      if (rows.some((row) => typeof row.time !== "number")) throw Error("Missing state timestamp");
      return {
        key: String(frameIndex),
        class: "space-y-2",
        attrs: {},
        heading: {
          class: "flex justify-between gap-3",
          label_container_class: "",
          label: {
            class: "text-xs font-medium",
            attrs: {},
            text: `${placementWidget(placement).title} · ${frameIndex + 1}`,
          },
          metadata_class: `flex flex-wrap gap-x-3 gap-y-1 ${muted}`,
          metadata: [],
          count: { class: muted, text: `${rows.length} observations` },
        },
        rows_class: "space-y-2",
        rows: rows.map((row, index) => ({
          key: String(index),
          class: "border-l-2 border-base-300 pl-3",
          attrs: {},
          content_class: "",
          heading_class: "flex gap-2",
          title: { class: "text-sm font-mono", text: label(row.normalized_state) },
          badges: [],
          // These are observations, not duration intervals. Do not invent a duration bar.
          bar: { class: "hidden", fill_class: "" },
          metadata_class: `flex flex-wrap gap-x-3 gap-y-1 ${muted}`,
          metadata: [
            timestamp(row.time),
            ...[row.label, row.resource_id, row.observable_id].filter((v) => v != null).map(String),
          ],
          actions_class: "hidden",
          link_menu: null,
        })),
      };
    }),
  };
}

export function snapshotWidgetBody(
  placement: WorkspacePlacement,
  snapshot: WorkspaceSnapshot,
  id: string,
  group: string,
): Body {
  const kind = placement.widget?.type ?? "value_tile";
  let content: Body["content"] = null;
  let message =
    placement.status === "unavailable"
      ? `Widget unavailable: ${placement.reason?.replaceAll("_", " ")}.`
      : "";
  if (!message) {
    const primary = placement.frames.filter((f) => f.role === "primary");
    if (!primary.some((f) => f.fields.some((field) => field.values.length > 0)))
      message = "No data in this snapshot.";
    else {
      try {
        content = ["value_tile", "time_series", "constellation_health"].includes(kind)
          ? { component: "WidgetPoint", presentation: point(placement, snapshot, id, group) }
          : {
              component: "WidgetRows",
              presentation: ["data_table", "status_matrix"].includes(kind)
                ? table(placement, id)
                : timeline(placement, id),
            };
      } catch {
        message = "This widget's frame shape cannot be displayed.";
      }
    }
  }
  const warnings = placement.warnings.map((w) => `${w.severity}: ${w.code.replaceAll("_", " ")}`);
  const nonPrimary = placement.frames.filter(
    (f) => f.role !== "primary" && !(kind === "time_series" && f.role === "compare"),
  );
  if (nonPrimary.length)
    warnings.push(
      `Additional frame roles: ${Array.from(new Set(nonPrimary.map((f) => f.role))).join(", ")}.`,
    );
  const notice = [message, ...warnings].filter(Boolean).join(" ");
  return {
    kind,
    root: {
      class: "min-h-0 flex-1 overflow-auto p-3",
      attrs: { "data-workspace-widget-body": placement.id },
    },
    content,
    notice: notice
      ? {
          kind: "notice",
          class: "mb-3 border-l-2 border-warning/50 pl-2 text-xs text-base-content/70",
          attrs: { role: "status" },
          text: notice,
          actions: [],
        }
      : null,
  };
}
