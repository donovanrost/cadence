type UploadError = {
  ref: string;
  error: string;
  code: string;
  message: string;
};

export type UploadEntry = {
  ref: string;
  client_name: string;
  client_size: number;
  client_type: string;
  progress: number;
  done: boolean;
  valid: boolean;
  preflighted: boolean;
  errors: string[];
};

type UploadConfig = {
  ref: string;
  name: string;
  accept: string | false;
  max_entries: number;
  max_file_size: number;
  auto_upload: boolean;
  entries: UploadEntry[];
  errors: UploadError[];
};

type UploadField = {
  key: string;
  id: string;
  name: string;
  type: "text" | "textarea";
  label: string;
  value: string;
  errors: string[];
  wrapper_class: string;
  label_class: string;
  input_class: string;
  error_class: string;
};

type UploadForm = {
  id: string;
  name: string;
  class: string;
  card: {
    id: string | null;
    class: string;
    body_class: string;
    title: string;
    title_class: string;
  };
  content_class: string | null;
  description: null | {
    text: string;
    class: string;
  };
  primary_fields_class: string;
  primary_fields: UploadField[];
  secondary_fields: UploadField[];
  file_input: {
    id: string;
    name: string;
    class: string;
    wrapper_class: string | null;
  };
  entries: {
    list_class: string;
    item_class: string;
    name_class: string;
    progress_class: string;
    remove_class: string;
    remove_label: string;
  };
  error_class: string;
  importer: {
    detected_class: string;
    icon_class: string;
    name_class: string;
    empty_class: string;
  };
  actions_class: string | null;
  submit: {
    id: string | null;
    label: string;
    class: string;
  };
};

type DetectedImporter = {
  status: "empty" | "unsupported" | "detected";
  display_name: string | null;
};

export type CatalogUploadFormProps = {
  form: UploadForm;
  upload: UploadConfig;
  detected_importer: DetectedImporter;
  submit_disabled: boolean;
};
