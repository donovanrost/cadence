export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type ProfilePage = {
  id: string;
  title: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
};

export type FormSection = {
  id: string;
  number: string;
  title: string;
  description: string | null;
};

export type FormField = {
  id: string;
  name: string;
  type: "text" | "number" | "select";
  label: string;
  required: boolean;
  value: string;
};

export type ApplicationField = {
  id: string;
  name: string;
  value: Record<string, string>;
};

export type ProfileForm = {
  id: string;
  sections: {
    identity: FormSection;
    protocols: FormSection;
    frame_parameters: FormSection;
    applications: FormSection;
  };
  fields: {
    display_name: FormField;
    downlink_protocol: FormField;
    uplink_protocol: FormField;
    frame_size: FormField;
    secondary_header_length: FormField;
    insert_zone_length: FormField;
    truncated_primary_header: FormField;
    ocf_length: FormField;
    applications: ApplicationField;
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

export type ProfileOptions = {
  downlink_protocols: SelectOption[];
  uplink_protocols: SelectOption[];
  truncated_primary_headers: SelectOption[];
  operational_control_fields: SelectOption[];
  frame_fields: {
    secondary_header_length: string[];
    insert_zone_length: string[];
    truncated_primary_header: string[];
  };
};

export type ApplicationOption = {
  id: string;
  key: string;
  name: string;
  value: string;
  label: string;
  description: string;
  available: boolean;
  availability_label: string | null;
};

export type ProfileValues = {
  display_name: string;
  downlink_protocol: string;
  uplink_protocol: string;
  frame_size: string;
  secondary_header_length: string;
  insert_zone_length: string;
  truncated_primary_header: string;
  ocf_length: string;
  applications: Record<string, string>;
};

export type ProfilePayload = {
  spacecraft_type: ProfileValues;
};

export type ProfileData = {
  page: ProfilePage;
  form: ProfileForm;
  options: ProfileOptions;
  applications: ApplicationOption[];
};
export type ProfileErrors = Partial<Record<keyof ProfileValues, string[]>>;
export type ProfileAction = (event: "validate" | "save", input: ProfilePayload) => Promise<unknown>;
