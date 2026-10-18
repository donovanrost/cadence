import {
  assertShape,
  attrs,
  bool,
  choice,
  count,
  element,
  href,
  label,
  list,
  nullable,
  shape,
  text,
  tone,
} from "../../shared/validation.ts";

const field = shape({
  key: text,
  id: text,
  name: text,
  type: choice("text", "textarea"),
  label: text,
  value: text,
  errors: list(text),
  wrapper_class: text,
  label_class: text,
  input_class: text,
  error_class: text,
});
export const uploadForm = shape({
  id: text,
  name: text,
  class: text,
  card: shape({
    id: nullable(text),
    class: text,
    body_class: text,
    title: text,
    title_class: text,
  }),
  content_class: nullable(text),
  description: nullable(shape({ text, class: text })),
  primary_fields_class: text,
  primary_fields: list(field),
  secondary_fields: list(field),
  file_input: shape({ id: text, name: text, class: text, wrapper_class: nullable(text) }),
  entries: shape({
    list_class: text,
    item_class: text,
    name_class: text,
    progress_class: text,
    remove_class: text,
    remove_label: text,
  }),
  error_class: text,
  importer: shape({ detected_class: text, icon_class: text, name_class: text, empty_class: text }),
  actions_class: nullable(text),
  submit: shape({ id: nullable(text), label: text, class: text }),
});
const uploadFields = {
  upload: shape({
    ref: text,
    name: text,
    accept: (value: unknown) => value === false || text(value),
    max_entries: count,
    max_file_size: count,
    auto_upload: bool,
    entries: list(
      shape({
        ref: text,
        client_name: text,
        client_size: count,
        client_type: text,
        progress: count,
        done: bool,
        valid: bool,
        preflighted: bool,
        errors: list(text),
      }),
    ),
    errors: list(shape({ ref: text, error: text, code: text, message: text })),
  }),
  detected_importer: shape({
    status: choice("empty", "unsupported", "detected"),
    display_name: nullable(text),
  }),
  submit_disabled: bool,
};
const link = shape({ label: text, href });
export const databaseRow = shape({
  id: text,
  actions_id: text,
  name: text,
  slug: text,
  href,
  latest_revision: nullable(link),
  latest_import: nullable(shape({ status: tone, status_label: text, href })),
});
export function assertDatabaseIndex(value: unknown): void {
  assertShape(
    shape({
      presentation: shape({
        root: element,
        header: shape({
          attrs,
          body: element,
          content: element,
          breadcrumbs: shape({ attrs, mission: label, separator: label, current: label }),
          title: label,
          subtitle: label,
          actions: element,
          new_database: shape({ attrs, text, icon: element }),
        }),
        empty_state: shape({
          visible: bool,
          list: element,
          root: element,
          title: label,
          description: label,
        }),
        card: shape({
          visible: bool,
          root: element,
          body: element,
          child_wrapper: element,
          rows: list(databaseRow),
        }),
      }),
    }),
    value,
  );
}
export function assertDatabaseNew(value: unknown): void {
  assertShape(
    shape({
      ...uploadFields,
      form: uploadForm,
      page: shape({
        id: text,
        heading: text,
        breadcrumbs: list(shape({ label: text, href: nullable(href) })),
        cancel: shape({ id: text, label: text, href }),
      }),
    }),
    value,
  );
}
export function assertDatabaseShow(value: unknown): void {
  assertShape(
    shape({
      ...uploadFields,
      revision_form: uploadForm,
      revision_form_open: bool,
      database: shape({
        id: text,
        name: text,
        slug: text,
        description: text,
        runtime_usage_summary: text,
      }),
      navigation: shape({ mission: link, catalog: link, current: shape({ label: text }) }),
      revisions: list(
        shape({
          id: text,
          revision_id: text,
          label: text,
          number: count,
          mission_model_revision_id: text,
          href,
        }),
      ),
      import_runs: list(
        shape({ id: text, run_id: text, status: shape({ value: text, label: text, tone }), href }),
      ),
    }),
    value,
  );
}
