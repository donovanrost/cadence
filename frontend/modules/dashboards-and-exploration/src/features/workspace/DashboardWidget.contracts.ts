import type { DashboardWidgetHeaderPresentation as HeaderPresentation } from "./DashboardWidgetHeader.contracts";
import type { WidgetPointPresentation as PointPresentation } from "./WidgetPoint.contracts";
import type { WidgetRowsPresentation as RowsPresentation } from "./WidgetRows.contracts";
export type Classes = string | string[];

export type Attributes = Record<string, string>;

export type ButtonType = "button" | "submit" | "reset";

export type WidgetNoticePresentation = {
  kind: "notice" | "lifecycle";
  class: Classes;
  attrs: Attributes;
  text: string;
  actions: Array<{
    key: string;
    type: ButtonType;
    class: string;
    attrs: Attributes;
    icon: { name: string; class: string };
    text: string;
  }>;
};

export type WidgetBodyPresentation = {
  kind:
    | "value_tile"
    | "time_series"
    | "status_matrix"
    | "data_table"
    | "state_timeline"
    | "event_timeline"
    | "constellation_health";
  root: { class: Classes; attrs: Attributes };
  notice: WidgetNoticePresentation | null;
  content:
    | { component: "WidgetPoint"; presentation: PointPresentation }
    | { component: "WidgetRows"; presentation: RowsPresentation }
    | null;
};

export type DashboardWidgetPresentation = {
  component_id: string;
  header: HeaderPresentation;
  body: WidgetBodyPresentation;
};
