export type Attrs = Record<string, string>;

export type ElementPresentation = {
  attrs: Attrs;
};

export type TextPresentation = ElementPresentation & {
  text: string;
};

export type ProviderRow = {
  id: string;
  display_name: string;
  provider_type: string;
  server_url: string;
  status: "ready" | "attention" | "blocked";
  status_label: string;
  account_binding: string;
  grant_binding: string;
  last_synced_at: string;
  version: string;
  href: string;
};

export type BreadcrumbItem = {
  key: string;
  separator: TextPresentation | null;
  link: TextPresentation | null;
  current: TextPresentation | null;
};

export type Presentation = {
  root: ElementPresentation;
  header: {
    attrs: Attrs;
    body: ElementPresentation;
    content: ElementPresentation;
    breadcrumbs: {
      attrs: Attrs;
      items: BreadcrumbItem[];
    };
    title: TextPresentation & {
      suffix: TextPresentation;
    };
    subtitle: TextPresentation;
    actions: {
      attrs: Attrs;
      new_provider: TextPresentation & {
        icon: ElementPresentation;
      };
    };
  };
  empty_state: {
    attrs: Attrs;
    title: TextPresentation;
    description: TextPresentation;
    action_container: ElementPresentation;
    action: TextPresentation & {
      icon: ElementPresentation;
    };
  } | null;
  card: {
    attrs: Attrs;
    body: ElementPresentation;
    table_component: ElementPresentation;
    rows: ProviderRow[];
  } | null;
};
