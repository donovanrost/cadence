export type Attrs = Record<string, string | null>;

export type ButtonType = "button" | "submit" | "reset";

export type IconPresentation = {
  name: string;
  class: string;
};

export type ItemPresentation = {
  key: string;
  kind: "data_link" | "evidence";
  type: ButtonType;
  class: string;
  attrs: Attrs;
  label: { text: string; class: string | null };
  secondary: { text: string; class: string } | null;
  icon: IconPresentation | null;
};

export type WidgetDataLinksPresentation = {
  kind:
    | "widget"
    | "status_matrix_row"
    | "data_table_row"
    | "state_timeline_row"
    | "event_timeline_row";
  component_id: string;
  overlay: { id: string; class: string; attrs: Attrs };
  trigger: {
    id: string;
    type: ButtonType;
    class: string;
    attrs: Attrs;
    content: {
      class: string;
      title: string;
      attrs: Attrs;
      icon: IconPresentation;
    };
  };
  panel: { id: string; class: string; hidden: boolean; attrs: Attrs };
  body: { class: string };
  items: ItemPresentation[];
};
