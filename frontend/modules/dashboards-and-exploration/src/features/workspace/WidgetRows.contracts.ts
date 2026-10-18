import type { WidgetDataLinksPresentation } from "./WidgetDataLinks.contracts";
export type Attributes = Record<string, string>;

export type BadgePresentation = {
  key?: string;
  tag: "button" | "span";
  class: string;
  attrs: Attributes;
  text: string;
};

export type TableCellPresentation = {
  key: string;
  class: string;
  attrs: Attributes;
  text: string | null;
  badges: BadgePresentation[];
  link_menu: WidgetDataLinksPresentation | null;
};

export type TableRowPresentation = {
  key: string;
  class: string;
  attrs: Attributes;
  cells: TableCellPresentation[];
};

export type TablePresentation = {
  kind: "status_matrix" | "data_table";
  component_id: string;
  root: { class: string };
  head: {
    class: string;
    row_class: string;
    cells: Array<{
      key: string;
      class: string;
      text: string;
      text_class: string | null;
    }>;
  };
  rows: TableRowPresentation[];
};

export type StateTimelinePresentation = {
  kind: "state_timeline";
  component_id: string;
  root: { class: string };
  lanes: Array<{
    key: string;
    class: string;
    attrs: Attributes;
    heading: {
      class: string;
      label_container_class: string;
      label: { class: string; attrs: Attributes; text: string };
      metadata_class: string;
      metadata: string[];
      count: { class: string; text: string };
    };
    rows_class: string;
    rows: Array<{
      key: string;
      class: string;
      attrs: Attributes;
      content_class: string;
      heading_class: string;
      title: { class: string; text: string };
      badges: BadgePresentation[];
      bar: { class: string; fill_class: string };
      metadata_class: string;
      metadata: string[];
      actions_class: string;
      link_menu: WidgetDataLinksPresentation | null;
    }>;
  }>;
};

export type EventTimelinePresentation = {
  kind: "event_timeline";
  component_id: string;
  root: { class: string };
  rows: Array<{
    key: string;
    class: string;
    attrs: Attributes;
    marker: { container_class: string; class: string };
    content_class: string;
    heading_class: string;
    category: { class: string; text: string };
    badges: BadgePresentation[];
    time: { class: string; text: string };
    title: { class: string; attrs: Attributes; text: string };
    metadata_class: string;
    metadata: string[];
    actions_class: string;
    link_menu: WidgetDataLinksPresentation | null;
  }>;
};

export type WidgetRowsPresentation =
  | TablePresentation
  | StateTimelinePresentation
  | EventTimelinePresentation;
