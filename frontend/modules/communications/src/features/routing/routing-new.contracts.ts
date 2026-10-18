export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type Page = {
  id: string;
  title: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
};

export type FormSection = {
  number: string;
  title: string;
};

export type FormField = {
  id: string;
  name: string;
  type: "text" | "select";
  label: string;
  required: boolean;
  value: string;
};

export type RoutingRuleForm = {
  id: string;
  sections: {
    intent: FormSection;
    transport: FormSection;
    policy: FormSection;
  };
  fields: {
    display_name: FormField;
    purpose_label: FormField;
    spacecraft_id: FormField;
    transport_ref: FormField;
    direction: FormField;
    role: FormField;
  };
  actions: {
    submit: { id: string; label: string };
    cancel: { id: string; label: string; href: string };
  };
};

export type SelectOption = {
  label: string;
  value: string;
};

export type RoutingRuleOptions = {
  spacecraft: SelectOption[];
  transports: SelectOption[];
  directions: SelectOption[];
  roles: SelectOption[];
};

export type RoutingRuleValues = {
  display_name: string;
  purpose_label: string;
  spacecraft_id: string;
  transport_ref: string;
  direction: string;
  role: string;
};

export type RoutingRulePayload = {
  routing_rule: RoutingRuleValues;
};
