export type AttrValue = string | number | boolean | null;
export type Attrs = Record<string, AttrValue>;

export type TextPresentation = {
  class: string;
  text: string;
};

export type RowPresentation = {
  key: string;
  label: TextPresentation;
  value: TextPresentation & { attrs: Attrs };
};

export type RowSectionPresentation = {
  attrs: Attrs;
  heading: TextPresentation;
  list_class: string;
  rows: RowPresentation[];
};

export type OptionPresentation = {
  label: string;
  value: string;
  selected: boolean;
  disabled: boolean;
  title: string | null;
};

export type FormFieldPresentation = {
  wrapper_class: string;
  label: TextPresentation;
  attrs: Attrs;
  options?: OptionPresentation[];
};

export type FormPresentation = {
  attrs: Attrs;
  hidden_fields: Attrs[];
  fields: FormFieldPresentation[];
  confirmation: {
    row: { attrs: Attrs };
    input: { attrs: Attrs };
    label: TextPresentation;
  };
  submit: {
    attrs: Attrs;
    icon_class: string;
    text: string;
  };
};

export type EffectPresentation = {
  attrs: Attrs;
  label: TextPresentation;
  summary: { attrs: Attrs; text: string };
};
