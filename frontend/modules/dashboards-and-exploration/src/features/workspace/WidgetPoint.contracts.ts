import type { TelemetryChartProps } from "./chart-props";
export type Attributes = Record<string, string>;

export type ChartDataManagementPresentation = {
  component_id: string;
  presentation: {
    root: { class: string; attrs: Attributes };
    comparison: {
      class: string;
      attrs: Attributes;
      text: string;
    } | null;
    badges: Array<{
      key: string;
      tag: "button" | "span";
      class: string;
      attrs: Attributes;
      text: string;
    }>;
  };
};

export type ValueTilePresentation = {
  kind: "value_tile";
  component_id: string;
  host: { class: string };
  value: {
    container_class: string;
    text: string;
    class: string;
    attrs: Attributes;
    unit: { text: string; class: string } | null;
  };
  timestamp: { text: string; class: string };
  comparison: { text: string; class: string; attrs: Attributes } | null;
};

export type TimeSeriesPresentation = {
  kind: "time_series";
  component_id: string;
  host: { class: string };
  stage: { class: string; attrs: Attributes };
  data_management: ChartDataManagementPresentation | null;
  chart: {
    component_id: string;
    class: string;
    props: TelemetryChartProps;
  };
};

export type SeverityBadgePresentation = {
  class: string;
  dot_class: string;
  count: number;
  count_class: string;
  label: string;
  label_class: string;
};

export type ConstellationHealthPresentation = {
  kind: "constellation_health";
  component_id: string;
  host: { class: string };
  badges: { class: string; items: SeverityBadgePresentation[] };
  spacecraft: {
    class: string;
    attrs: Attributes;
    items: Array<{ key: string; class: string; attrs: Attributes }>;
  };
};

export type WidgetPointPresentation =
  | ValueTilePresentation
  | TimeSeriesPresentation
  | ConstellationHealthPresentation;
