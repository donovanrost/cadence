export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type SpacecraftPage = {
  id: string;
  heading: string;
  subtitle: string;
  breadcrumbs: Breadcrumb[];
};

export type Section = {
  id: string;
  number: string;
  title: string;
};

export type TextField = {
  id: string;
  name: string;
  type: "text";
  label: string;
  required: boolean;
  value: string;
};

export type SelectField = {
  id: string;
  name: string;
  type: "select";
  label: string;
  required: boolean;
  value: string;
};

export type SpacecraftForm = {
  id: string;
  profile_version: number | null;
  sections: {
    identity: Section;
    profile: Section;
  };
  fields: {
    display_name: TextField;
    scid: TextField;
    spacecraft_type_id: SelectField;
  };
  actions: {
    submit: { id: string; label: string };
    cancel: { id: string; label: string; href: string };
  };
};

export type ProfileOptions = {
  options: { label: string; value: string; version: number | null }[];
  empty: boolean;
  empty_state: {
    message: string;
    action: { id: string; label: string; href: string };
    suffix: string;
  };
};

export type SpacecraftValues = {
  spacecraft_type_version: number | null;
  display_name: string;
  scid: string;
  spacecraft_type_id: string;
};

export type SpacecraftPayload = {
  spacecraft: SpacecraftValues;
};

export type IdentityData = {
  page: SpacecraftPage;
  form: SpacecraftForm;
  profile_options: ProfileOptions;
};
export type IdentityErrors = Partial<Record<keyof SpacecraftValues, string[]>>;
export type IdentityAction = (
  event: "validate" | "save",
  input: SpacecraftPayload,
) => Promise<unknown>;
