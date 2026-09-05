defmodule CadenceWeb.CatalogDatabaseNewLive do
  @moduledoc false

  # Authz note: any signed-in mission member can create a catalog database.
  # Tighten once platform-wide authorization is defined.
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission

    {:ok,
     socket
     |> assign(:page_title, "New catalog database")
     |> assign(:nav_item, :catalog)
     |> assign(:page, page_dto(mission))
     |> assign(:database_form, empty_database_form())
     |> allow_upload(:artifact,
       accept: :any,
       max_entries: 1,
       max_file_size: 50 * 1024 * 1024
     )}
  end

  @impl true
  def handle_event("validate", %{"catalog_database" => params}, socket) do
    {:noreply, assign(socket, :database_form, to_form(params, as: :catalog_database))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :artifact, ref)}
  end

  def handle_event("save", params, socket) do
    form_params = Map.get(params, "catalog_database", %{})

    case detect_importer_from_entries(socket.assigns.uploads.artifact.entries) do
      {:ok, registration} ->
        perform_upload(socket, registration, form_params)

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Pick a file with a supported format before uploading."
         )}
    end
  end

  defp perform_upload(socket, %{descriptor: descriptor}, form_params) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    uploaded_by = uploader_identity(socket)

    [artifact_or_error | _] =
      consume_uploaded_entries(socket, :artifact, fn %{path: path}, entry ->
        case File.read(path) do
          {:ok, bytes} ->
            upload = %{
              filename: entry.client_name,
              bytes: bytes,
              client_type: entry.client_type
            }

            {:ok, {upload, descriptor}}

          {:error, reason} ->
            {:ok, {:error, {:file_read_failed, reason}}}
        end
      end)

    case artifact_or_error do
      {%{filename: filename} = upload, descriptor} ->
        with {:ok, database} <-
               create_catalog_database(
                 organization_id,
                 mission.mission_id,
                 descriptor,
                 form_params,
                 filename,
                 uploaded_by
               ),
             artifact <-
               Artifact.build_from_upload(mission.mission_id, descriptor, upload,
                 uploaded_by: uploaded_by,
                 catalog_database_id: database.catalog_database_id
               ),
             {:ok, run} <-
               Catalog.start_revision_import(
                 organization_id,
                 mission.mission_id,
                 database.catalog_database_id,
                 artifact,
                 descriptor.importer_key,
                 requested_by: uploaded_by,
                 importer_version: descriptor.version,
                 metadata: revision_metadata(form_params)
               ) do
          {:noreply,
           push_navigate(socket,
             to: ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}"
           )}
        else
          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to start revision import: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to read uploaded file: #{inspect(reason)}")}
    end
  end

  defp create_catalog_database(
         organization_id,
         mission_id,
         descriptor,
         form_params,
         filename,
         uploaded_by
       ) do
    name = normalize(form_params["name"]) || filename |> Path.rootname() |> String.trim()
    revision_label = normalize(form_params["revision_label"]) || "Revision 1"

    Catalog.create_database(organization_id, mission_id, %{
      name: name,
      slug: slugify(name),
      catalog_family: descriptor.catalog_family,
      default_importer_key: descriptor.importer_key,
      created_by: uploaded_by,
      metadata: %{"initial_revision_label" => revision_label}
    })
  end

  defp revision_metadata(form_params) do
    %{
      "revision_label" => normalize(form_params["revision_label"]) || "Revision 1",
      "revision_notes" => normalize(form_params["revision_notes"]) || ""
    }
  end

  defp uploader_identity(socket) do
    case socket.assigns.current_scope do
      %{user: %{id: id, email: email}} -> %{user_id: id, email: email}
      %{user: %{email: email}} -> %{email: email}
      _ -> %{}
    end
  end

  defp empty_database_form do
    to_form(%{"name" => "", "revision_label" => "", "revision_notes" => ""},
      as: :catalog_database
    )
  end

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_other), do: nil

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <form
        id="catalog-upload-live-form"
        phx-change="validate"
        phx-submit="save"
        style="display: none"
      >
        <.live_file_input upload={@uploads.artifact} />
      </form>

      <.vue
        id="catalog-database-new-component"
        v-component="FederatedFullPageSurface"
        page={@page}
        form={database_upload_form_dto(@database_form)}
        upload={upload_dto(@uploads.artifact)}
        detected_importer={detected_importer_dto(@uploads.artifact.entries)}
        submit_disabled={submit_disabled?(@uploads.artifact.entries)}
        v-on:validate={JS.push("validate")}
        v-on:cancel-upload={JS.push("cancel_upload")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp page_dto(mission) do
    %{
      id: "catalog-database-new-page",
      heading: "New catalog database",
      breadcrumbs: [
        %{
          label: mission.display_name,
          href: ~p"/missions/#{mission.mission_id}"
        },
        %{
          label: "Catalog",
          href: ~p"/missions/#{mission.mission_id}/catalog"
        },
        %{label: "New database", href: nil}
      ],
      cancel: %{
        id: "catalog-database-new-cancel",
        label: "Cancel",
        href: ~p"/missions/#{mission.mission_id}/catalog"
      }
    }
  end

  defp database_upload_form_dto(form) do
    %{
      id: "catalog-upload-form",
      name: "catalog_database",
      class: "space-y-4",
      card: %{
        id: nil,
        class: "card bg-base-200 border border-base-300",
        body_class: "card-body p-6",
        title: "Create catalog database revision",
        title_class: "hud-label"
      },
      content_class: "space-y-4 mt-2",
      description: %{
        text:
          "Save the upload as an immutable revision in the mission catalog library. Runtime usage is chosen separately.",
        class: "text-sm text-base-content/70"
      },
      primary_fields_class: "grid grid-cols-1 md:grid-cols-2 gap-4",
      primary_fields: [
        upload_field_dto(
          "catalog_database",
          "name",
          "text",
          "Catalog database name",
          form.params
        ),
        upload_field_dto(
          "catalog_database",
          "revision_label",
          "text",
          "Revision label",
          form.params
        )
      ],
      secondary_fields: [
        upload_field_dto(
          "catalog_database",
          "revision_notes",
          "textarea",
          "Revision notes",
          form.params
        )
      ],
      file_input: %{
        id: "catalog-upload-file-input",
        name: "artifact",
        class: "file-input file-input-bordered w-full",
        wrapper_class: "block"
      },
      entries: upload_entries_presentation(),
      error_class: "border px-4 py-3 text-sm text-base-content border-error/40 bg-error/10",
      importer: importer_presentation(),
      actions_class: "flex items-center gap-3",
      submit: %{
        id: nil,
        label: "Upload & import",
        class: "btn btn-primary"
      }
    }
  end

  defp upload_field_dto(form_name, key, type, label, params) do
    %{
      key: key,
      id: "#{form_name}_#{key}",
      name: "#{form_name}[#{key}]",
      type: type,
      label: label,
      value: string_param(params, key),
      errors: [],
      wrapper_class: "fieldset mb-3",
      label_class: "hud-label block mb-1.5",
      input_class: if(type == "textarea", do: "w-full textarea", else: "w-full input"),
      error_class: "mt-1.5 text-sm text-error"
    }
  end

  defp upload_entries_presentation do
    %{
      list_class: "space-y-1",
      item_class: "flex items-center justify-between text-sm",
      name_class: "font-mono",
      progress_class: "progress progress-primary h-1 w-24",
      remove_class: "btn btn-ghost btn-xs",
      remove_label: "Remove"
    }
  end

  defp importer_presentation do
    %{
      detected_class: "flex items-center gap-2 text-sm text-base-content/80",
      icon_class: "hero-check-circle h-4 w-4 text-success",
      name_class: "font-medium",
      empty_class: "text-xs text-base-content/60"
    }
  end

  defp submit_disabled?(entries) do
    entries
    |> detect_importer_from_entries()
    |> importer_detected?()
    |> Kernel.not()
  end

  defp string_param(params, key) do
    case Map.get(params, key, "") do
      value when is_binary(value) -> value
      _other -> ""
    end
  end
end
