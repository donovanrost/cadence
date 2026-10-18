export type Attrs = Record<string, string>;

export type ButtonType = "button" | "submit" | "reset";

export type TextPresentation = {
  class: string;
  text: string;
};

export type FieldPresentation = {
  key: string;
  label: TextPresentation;
  value: TextPresentation;
};

export type WidgetWarningPresentation = {
  component_id: string;
  overlay: { id: string; class: string; attrs: Attrs };
  trigger: {
    id: string;
    type: ButtonType;
    class: string;
    attrs: Attrs;
    badge: { class: string; attrs: Attrs; text: string };
  };
  panel: { id: string; class: string; hidden: boolean; attrs: Attrs };
  body: {
    class: string;
    heading: TextPresentation;
    message: TextPresentation;
    evidence_button: {
      type: ButtonType;
      class: string;
      attrs: Attrs;
      icon: { name: string; class: string };
      text: string;
    };
    details: {
      visible: boolean;
      class: string;
      rows: Array<{
        key: string;
        label: TextPresentation;
        value: TextPresentation & { attrs: Attrs };
      }>;
    };
    evidence: {
      visible: boolean;
      class: string;
      attrs: Attrs;
      heading: TextPresentation;
      rows: Array<{ key: string; class: string; attrs: Attrs; fields: FieldPresentation[] }>;
    };
    links: {
      visible: boolean;
      class: string;
      attrs: Attrs;
      heading: TextPresentation;
      rows: Array<{
        key: string;
        type: ButtonType;
        class: string;
        attrs: Attrs;
        fields: FieldPresentation[];
      }>;
    };
  };
};
