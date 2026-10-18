import { catalogHref, element, label } from "../../shared/test-support";
export function databaseIndexFixture() {
  return {
    presentation: {
      root: element(),
      header: {
        attrs: {},
        body: element(),
        content: element(),
        breadcrumbs: {
          attrs: {},
          mission: { ...label("Mission"), attrs: { href: "/missions/mission-a" } },
          separator: label("/"),
          current: label(),
        },
        title: label(),
        subtitle: label("Mission databases"),
        actions: element(),
        new_database: {
          attrs: { id: "new-database-link", href: `${catalogHref}/new` },
          text: "New database",
          icon: element(),
        },
      },
      empty_state: {
        visible: false,
        list: element(),
        root: element(),
        title: label(),
        description: label(),
      },
      card: {
        visible: true,
        root: element(),
        body: element(),
        child_wrapper: element(),
        rows: [
          {
            id: "database-row-one",
            actions_id: "database-one-actions",
            name: "Flight database",
            slug: "flight",
            href: `${catalogHref}/databases/one`,
            latest_revision: { label: "Revision 1", href: `${catalogHref}/revisions/one` },
            latest_import: {
              status: "ready" as const,
              status_label: "Completed",
              href: `${catalogHref}/imports/one`,
            },
          },
        ],
      },
    },
  };
}
export function databaseUploadFixture() {
  return {
    form: {
      id: "catalog-upload-form",
      name: "catalog_database",
      class: "",
      card: { id: null, class: "", body_class: "", title: "Import", title_class: "" },
      content_class: null,
      description: null,
      primary_fields_class: "",
      primary_fields: [
        {
          key: "name",
          id: "catalog_database_name",
          name: "catalog_database[name]",
          type: "text" as const,
          label: "Name",
          value: "",
          errors: [],
          wrapper_class: "",
          label_class: "",
          input_class: "",
          error_class: "",
        },
      ],
      secondary_fields: [],
      file_input: {
        id: "catalog-upload-file-input",
        name: "artifact",
        class: "",
        wrapper_class: null,
      },
      entries: {
        list_class: "",
        item_class: "",
        name_class: "",
        progress_class: "",
        remove_class: "",
        remove_label: "Remove",
      },
      error_class: "",
      importer: { detected_class: "", icon_class: "", name_class: "", empty_class: "" },
      actions_class: null,
      submit: { id: "catalog-upload-submit", label: "Upload", class: "" },
    },
    upload: {
      ref: "artifact",
      name: "artifact",
      accept: false as const,
      max_entries: 1,
      max_file_size: 52428800,
      auto_upload: false,
      entries: [],
      errors: [],
    },
    detected_importer: { status: "empty" as const, display_name: null },
    submit_disabled: true,
  };
}
export function databaseNewFixture() {
  return {
    ...databaseUploadFixture(),
    page: {
      id: "catalog-database-new-page",
      heading: "New database",
      breadcrumbs: [{ label: "Catalog", href: catalogHref }],
      cancel: { id: "catalog-database-new-cancel", label: "Cancel", href: catalogHref },
    },
  };
}
export function databaseShowFixture() {
  const { form, ...upload } = databaseUploadFixture();
  return {
    ...upload,
    database: {
      id: "one",
      name: "Flight database",
      slug: "flight",
      description: "Immutable revisions",
      runtime_usage_summary: "No runtime bindings yet.",
    },
    navigation: {
      mission: { label: "Mission", href: "/missions/mission-a" },
      catalog: { label: "Catalog", href: catalogHref },
      current: { label: "Flight database" },
    },
    revision_form_open: false,
    revision_form: form,
    revisions: [
      {
        id: "revision-row-one",
        revision_id: "one",
        label: "Revision 1",
        number: 1,
        mission_model_revision_id: "model-one",
        href: `${catalogHref}/revisions/one`,
      },
    ],
    import_runs: [
      {
        id: "import-row-one",
        run_id: "one",
        status: { value: "completed", label: "Completed", tone: "ready" as const },
        href: `${catalogHref}/imports/one`,
      },
    ],
  };
}
