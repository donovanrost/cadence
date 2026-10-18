export type Breadcrumb = {
  label: string;
  href: string | null;
};

export type Page = {
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

export type Field = {
  id: string;
  name: string;
  type: "text" | "textarea";
  label: string;
  required: boolean;
  disabled: boolean;
  placeholder: string | null;
  value: string;
};

export type GroundStationForm = {
  id: string;
  sections: {
    identity: Section;
    network: Section;
    metadata: Section;
  };
  fields: {
    ground_station_id: Field;
    display_name: Field;
    provider: Field;
    region: Field;
    metadata_json: Field;
  };
  actions: {
    submit: { id: string; label: string };
    cancel: { id: string; label: string; href: string };
  };
};

export type GroundStationValues = {
  ground_station_id: string;
  display_name: string;
  provider: string;
  region: string;
  metadata_json: string;
};

export type GroundStationPayload = {
  ground_station: GroundStationValues;
};
