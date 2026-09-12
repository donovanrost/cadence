import type { DashboardWidgetPresentation } from "./DashboardWidget.contracts";

type Element = { attrs: Record<string, string> };
type Text = Element & { text: string };
export type GridOptions = {
  target_id: string;
  item_ids: readonly string[];
  edit_mode: boolean;
  columns?: number;
  row_height_px?: number;
  gap_px?: number;
};
export type GridPresentation = {
  root: Element;
  widgets: {
    key: string;
    shell: Element;
    content: Element;
    host: Element;
    presentation: DashboardWidgetPresentation;
  }[];
  controller: { host: Element; props: GridOptions };
};
export type CanvasSection = {
  root: { attrs: Record<string, string> & { id: string } };
  summary: Element & {
    icon: Element;
    copy: Element & { title: Text; description: Text | null };
    count: Text | null;
  };
};
export type CanvasGroup = {
  key: string;
  root: Element;
  section: CanvasSection | null;
  header?: (Element & { icon: Element; title: Text; count: Text | null }) | null;
  grid: GridPresentation;
};
export type CanvasPresentation = {
  root: Element;
  content: Element;
  groups: CanvasGroup[];
  empty_state: null | {
    wrapper: Element;
    card: Element;
    icon: Element;
    title: Text;
    message: Text;
    actions: Element & { action: null | (Text & { kind: "button" | "link"; icon: Element }) };
  };
};
/** GridStack may expose an incomplete node while it initializes. The receiving native action owns admission. */
export type LayoutChanged = {
  layouts: {
    widget_id: string | null;
    x: number | undefined;
    y: number | undefined;
    w: number | undefined;
    h: number | undefined;
  }[];
};
