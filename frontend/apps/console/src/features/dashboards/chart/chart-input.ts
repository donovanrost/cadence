import type { ChartEnvelope, ChartPoint } from "./chart-points.ts";

export const textValue = (value: unknown): string | null =>
  typeof value === "string" && value ? value : null;

export type ChartSeries = {
  id: string;
  label: string;
  observable_id: string | null;
  unit: string | null;
  source: unknown;
  frame_id: string | null;
  field: string | null;
  time_axis: string | null;
  sampling: unknown;
  decimation: unknown;
  data_source_id: string | null;
  source_binding_id: string | null;
  role: string;
  compare_of: string | null;
  envelope: ChartEnvelope | null;
  points: ChartPoint[];
};
export type PlotSeries =
  | { kind: "line"; seriesIndex: number }
  | { kind: "envelope_low" | "envelope_high"; seriesIndex: number; values: (number | null)[] };
