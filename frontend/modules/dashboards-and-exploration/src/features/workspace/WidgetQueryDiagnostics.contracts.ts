export type Attrs = Record<string, string>;

export type ButtonType = "button" | "submit" | "reset";

export type IconPresentation = {
  name: string;
  class: string;
};

export type TextPresentation = {
  class: string;
  text: string;
};

export type RowPresentation = {
  key: string;
  order: number;
  label: TextPresentation & { attrs: Attrs };
  value: TextPresentation & { attrs: Attrs };
};

export type WidgetQueryDiagnosticsPresentation = {
  component_id: string;
  overlay: { id: string; class: string; attrs: Attrs };
  trigger: {
    id: string;
    type: ButtonType;
    class: string;
    attrs: Attrs;
    content: { class: string; attrs: Attrs; icon: IconPresentation };
  };
  panel: { id: string; class: string; hidden: boolean; attrs: Attrs };
  body: {
    class: string;
    heading: TextPresentation;
    rows_class: string;
    rows: RowPresentation[];
    evidence_button: {
      type: ButtonType;
      class: string;
      attrs: Attrs;
      icon: IconPresentation;
      text: string;
    };
  };
};
