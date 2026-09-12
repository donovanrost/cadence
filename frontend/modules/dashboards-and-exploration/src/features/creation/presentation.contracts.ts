export type CloneSource = {
  id: string;
  dashboard_id: string;
  name: string;
  widget_count: number;
  latest_version: number;
};

export type Page = {
  id: string;
  mode: "new" | "clone" | "import";
  eyebrow: string;
  heading: string;
  description: string;
  source: CloneSource | null;
  import_guidance: string | null;
  cancel: {
    id: string;
    label: string;
    href: string;
  };
};

export type TextField = {
  id: string;
  name: string;
  type: "text";
  label: string;
  value: string;
  required: boolean;
};

export type DocumentJsonField = {
  id: string;
  name: string;
  type: "textarea";
  label: string;
  value: string;
  required: boolean;
};

export type DashboardForm = {
  id: string;
  name: TextField;
  description: TextField;
  document_json: DocumentJsonField | null;
  submit: {
    id: string;
    label: string;
  };
};

export type DashboardValues = {
  name: string;
  description: string;
  document_json: string;
};

export type DashboardPayload = {
  dashboard: {
    name: string;
    description: string;
    document_json?: string;
  };
};
