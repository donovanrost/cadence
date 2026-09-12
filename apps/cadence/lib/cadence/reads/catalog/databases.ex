defmodule Cadence.Reads.Catalog.Databases do
  @moduledoc false

  import Cadence.Reads.Catalog.Presentation

  alias Cadence.Catalog

  def catalog_index(organization_id, mission_id) do
    databases = Catalog.list_databases(organization_id, mission_id)
    revisions = Catalog.latest_revision_by_database(organization_id, mission_id)
    runs = Catalog.latest_import_run_by_database(organization_id, mission_id)

    rows =
      Enum.map(databases, fn database ->
        revision = Map.get(revisions, database.catalog_database_id)
        run = Map.get(runs, database.catalog_database_id)

        %{
          "id" => "catalog-database-row-#{database.catalog_database_id}",
          "actions_id" => "#{database.catalog_database_id}-actions",
          "name" => database.name,
          "slug" => database.slug,
          "href" => "/missions/#{mission_id}/catalog/databases/#{database.catalog_database_id}",
          "latest_revision" =>
            revision &&
              %{
                "label" => revision.revision_label,
                "href" =>
                  "/missions/#{mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
              },
          "latest_import" =>
            run &&
              %{
                "status" => import_status_tone(run.status),
                "status_label" => import_status_label(run.status),
                "href" => "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
              }
        }
      end)

    {:ok,
     %{
       "presentation" => %{
         "root" => %{"attrs" => %{"class" => "space-y-6"}},
         "header" => catalog_header(mission_id),
         "empty_state" => %{
           "visible" => rows == [],
           "list" => %{"attrs" => %{"id" => "catalog-database-list"}},
           "root" => %{
             "attrs" => %{
               "class" =>
                 "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
             }
           },
           "title" => %{
             "attrs" => %{"class" => "hud-label"},
             "text" => "No catalog databases yet"
           },
           "description" => %{
             "attrs" => %{"class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"},
             "text" => "Use + New database above to import the first revision."
           }
         },
         "card" => %{
           "visible" => rows != [],
           "root" => %{
             "attrs" => %{
               "class" => "card bg-base-200 border border-base-300",
               "id" => "catalog-database-list"
             }
           },
           "body" => %{"attrs" => %{"class" => "card-body p-0"}},
           "child_wrapper" => %{"attrs" => %{"id" => "catalog-databases-table-component"}},
           "rows" => rows
         }
       }
     }}
  end

  def catalog_database_new_data(mission_id) do
    %{
      "page" => %{
        "id" => "catalog-database-new-page",
        "heading" => "New catalog database",
        "breadcrumbs" => [
          %{"label" => "Mission", "href" => nil},
          %{"label" => "Catalog", "href" => nil},
          %{"label" => "New database", "href" => nil}
        ],
        "cancel" => %{
          "id" => "catalog-database-new-cancel",
          "label" => "Cancel",
          "href" => "/missions/#{mission_id}/catalog"
        }
      },
      "form" =>
        upload_form(
          "catalog-upload-form",
          "catalog_database",
          "Create catalog database revision",
          "Upload & import",
          nil
        ),
      "upload" => upload_config("artifact"),
      "detected_importer" => %{"status" => "empty", "display_name" => nil},
      "submit_disabled" => true
    }
  end

  def catalog_database_show(organization_id, mission_id, params) do
    with {:ok, database_id} <- subject_id(params, "catalog_database_id"),
         {:ok, database} <- Catalog.fetch_database(organization_id, mission_id, database_id) do
      revisions = Catalog.list_revisions(organization_id, mission_id, database_id)

      runs =
        Catalog.list_import_runs(organization_id, mission_id, catalog_database_id: database_id)

      {:ok,
       %{
         "database" => %{
           "id" => database.catalog_database_id,
           "name" => database.name,
           "slug" => database.slug,
           "description" =>
             database.description ||
               "Mission catalog library entry. Add immutable revisions here, then choose runtime usage separately.",
           "runtime_usage_summary" => "No runtime bindings yet."
         },
         "navigation" => %{
           "mission" => %{"label" => "Mission", "href" => mission_href(mission_id)},
           "catalog" => %{"label" => "Catalog", "href" => "/missions/#{mission_id}/catalog"},
           "current" => %{"label" => database.name}
         },
         "revision_form_open" => false,
         "revision_form" =>
           upload_form(
             "catalog-revision-upload-form",
             "catalog_revision",
             "Add revision",
             "Upload revision",
             "catalog-revision-upload-card"
           ),
         "upload" => upload_config("artifact"),
         "detected_importer" => %{"status" => "empty", "display_name" => nil},
         "submit_disabled" => true,
         "revisions" => Enum.map(revisions, &revision_row(&1, mission_id)),
         "import_runs" => Enum.map(runs, &import_run_row(&1, mission_id))
       }}
    end
  end

  defp revision_row(revision, mission_id),
    do: %{
      "id" => "catalog-revision-row-#{revision.catalog_revision_id}",
      "revision_id" => revision.catalog_revision_id,
      "label" => revision.revision_label,
      "number" => revision.revision_number,
      "mission_model_revision_id" => revision.mission_model_revision_id,
      "href" => "/missions/#{mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
    }

  defp import_run_row(run, mission_id),
    do: %{
      "id" => "catalog-import-run-row-#{run.import_run_id}",
      "run_id" => run.import_run_id,
      "status" => %{
        "value" => atom_string(run.status),
        "label" => import_status_label(run.status),
        "tone" => import_status_tone(run.status)
      },
      "href" => "/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
    }

  defp upload_form(id, name, title, submit_label, card_id) do
    %{
      "id" => id,
      "name" => name,
      "class" => "space-y-4",
      "card" => %{
        "id" => card_id,
        "class" => "card bg-base-200 border border-base-300",
        "body_class" => "card-body p-6",
        "title" => title,
        "title_class" => "hud-label"
      },
      "content_class" => if(name == "catalog_database", do: "space-y-4 mt-2", else: nil),
      "description" =>
        if(name == "catalog_database",
          do: %{
            "text" =>
              "Save the upload as an immutable revision in the mission catalog library. Runtime usage is chosen separately.",
            "class" => "text-sm text-base-content/70"
          },
          else: nil
        ),
      "primary_fields_class" => "grid grid-cols-1 md:grid-cols-2 gap-4",
      "primary_fields" => upload_fields(name),
      "secondary_fields" =>
        if(name == "catalog_database",
          do: [upload_field(name, "revision_notes", "textarea", "Revision notes")],
          else: []
        ),
      "file_input" => %{
        "id" =>
          if(name == "catalog_database",
            do: "catalog-upload-file-input",
            else: "catalog-revision-upload-file-input"
          ),
        "name" => "artifact",
        "class" => "file-input file-input-bordered w-full",
        "wrapper_class" => if(name == "catalog_database", do: "block", else: nil)
      },
      "entries" => upload_entries(),
      "error_class" => "border px-4 py-3 text-sm text-base-content border-error/40 bg-error/10",
      "importer" => importer_presentation(),
      "actions_class" => if(name == "catalog_database", do: "flex items-center gap-3", else: nil),
      "submit" => %{
        "id" => if(name == "catalog_database", do: nil, else: "catalog-revision-upload-submit"),
        "label" => submit_label,
        "class" => "btn btn-primary"
      }
    }
  end

  defp upload_fields(name),
    do: [
      upload_field(
        name,
        "#{if(name == "catalog_database", do: "name", else: "revision_label")}",
        "text",
        if(name == "catalog_database", do: "Catalog database name", else: "Revision label")
      ),
      upload_field(
        name,
        if(name == "catalog_database", do: "revision_label", else: "revision_notes"),
        "text",
        if(name == "catalog_database", do: "Revision label", else: "Notes")
      )
    ]

  defp upload_field(form_name, key, type, label),
    do: %{
      "key" => key,
      "id" => "#{form_name}_#{key}",
      "name" => "#{form_name}[#{key}]",
      "type" => type,
      "label" => label,
      "value" => "",
      "errors" => [],
      "wrapper_class" => "fieldset mb-3",
      "label_class" => "hud-label block mb-1.5",
      "input_class" => if(type == "textarea", do: "w-full textarea", else: "w-full input"),
      "error_class" => "mt-1.5 text-sm text-error"
    }

  defp upload_entries,
    do: %{
      "list_class" => "space-y-1",
      "item_class" => "flex items-center justify-between text-sm",
      "name_class" => "font-mono",
      "progress_class" => "progress progress-primary h-1 w-24",
      "remove_class" => "btn btn-ghost btn-xs",
      "remove_label" => "Remove"
    }

  defp importer_presentation,
    do: %{
      "detected_class" => "flex items-center gap-2 text-sm text-base-content/80",
      "icon_class" => "hero-check-circle h-4 w-4 text-success",
      "name_class" => "font-medium",
      "empty_class" => "text-xs text-base-content/60"
    }

  defp upload_config(ref),
    do: %{
      "ref" => ref,
      "name" => "artifact",
      "accept" => false,
      "max_entries" => 1,
      "max_file_size" => 52_428_800,
      "auto_upload" => false,
      "entries" => [],
      "errors" => []
    }

  defp catalog_header(mission_id),
    do: %{
      "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
      "body" => %{"attrs" => %{"class" => "flex items-end justify-between gap-4"}},
      "content" => %{"attrs" => %{}},
      "breadcrumbs" => catalog_breadcrumbs(mission_id),
      "title" => %{
        "attrs" => %{"class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"},
        "text" => "Catalog"
      },
      "subtitle" => %{
        "attrs" => %{"class" => "mt-1 max-w-3xl text-sm text-base-content/70"},
        "text" =>
          "Mission database library. Revisions are imported here; runtime usage is selected later."
      },
      "actions" => %{"attrs" => %{"class" => "flex items-center gap-2"}},
      "new_database" => %{
        "attrs" =>
          Map.merge(navigate_attrs("/missions/#{mission_id}/catalog/new"), %{
            "id" => "new-database-link"
          }),
        "icon" => %{"attrs" => %{"class" => "hero-plus h-4 w-4"}},
        "text" => "New database"
      }
    }
end
