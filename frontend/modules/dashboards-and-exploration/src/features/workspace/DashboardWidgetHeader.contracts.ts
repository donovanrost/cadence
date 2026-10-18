import type { WidgetWarningPresentation as WarningPresentation } from "./WidgetWarning.contracts";
import type { WidgetQueryDiagnosticsPresentation as QueryPresentation } from "./WidgetQueryDiagnostics.contracts";
import type { WidgetDataLinksPresentation as DataLinksPresentation } from "./WidgetDataLinks.contracts";
export type Attrs = Record<string, string>;

export type Classes = string | string[];

export type ButtonType = "button" | "submit" | "reset";

export type IconPresentation = {
  name: string;
  class: string;
};

export type BadgePresentation = {
  class: Classes;
  text: string;
};

export type ButtonPresentation = {
  key?: string;
  type: ButtonType;
  class: string;
  attrs: Attrs;
  icon: IconPresentation;
};

export type SourceBadgePresentation = {
  wrapper: { tag: string; class: string } | null;
  badge: {
    tag: string;
    class: string;
    attrs: Attrs;
    icon: IconPresentation;
    text: string;
  };
  inventory_link: {
    tag: string;
    class: string;
    attrs: Attrs;
    icon: IconPresentation;
  } | null;
};

export type DashboardWidgetHeaderPresentation = {
  component_id: string;
  root: { class: Classes; attrs: Attrs };
  title: { class: Classes; text: string };
  status_indicators: {
    class: string;
    attrs: Attrs;
    limit: {
      class: Classes;
      dot_class: string;
      label_class: string;
      text: string;
    } | null;
    comparison: ({ attrs: Attrs } & BadgePresentation) | null;
    quality: BadgePresentation | null;
    lifecycle: {
      class: Classes;
      attrs: Attrs;
      icon: IconPresentation;
    } | null;
  };
  actions: {
    class: Classes;
    details: {
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
        heading: {
          class: string;
          title: { class: string; text: string };
          binding: { class: string; text: string };
        };
        indicators: {
          class: string;
          attrs: Attrs;
          lifecycle: BadgePresentation | null;
          source: SourceBadgePresentation | null;
          data_management: Array<{ tag: string; class: string; attrs: Attrs; text: string }>;
          warnings: WarningPresentation[];
        };
        actions: {
          class: string;
          attrs: Attrs;
          query: QueryPresentation | null;
          frame_evidence: ButtonPresentation | null;
          data_links: DataLinksPresentation | null;
          inspector: ButtonPresentation | null;
        };
      };
    };
    edit: ButtonPresentation[];
  };
};
