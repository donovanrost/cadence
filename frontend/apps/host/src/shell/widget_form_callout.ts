import type { Attributes } from "@cadence/ui/widget_form_field";

export type IconPresentation = {
  name: string;
  class: string;
};

export type CalloutPresentation = {
  class: string;
  attrs: Attributes;
  icon: IconPresentation;
  text: string;
};
