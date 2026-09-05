defmodule CadenceWeb.CatalogDatabaseShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Events

  @default_database_description "Mission catalog library entry. Add immutable revisions here, then choose runtime usage separately."

  @impl true
  def mount(%{"catalog_database_id" => catalog_database_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    case Catalog.fetch_database(organization_id, mission.mission_id, catalog_database_id) do
      {:ok, database} ->
        if connected?(socket), do: Events.subscribe_import_runs(mission.mission_id)

        {:ok,
         socket
         |> assign(:page_title, database.name)
         |> assign(:nav_item, :catalog)
         |> assign(:database, database)
         |> assign(:database_details, database_details_dto(database))
         |> assign(:navigation, navigation_dto(mission, database))
         |> assign(:revision_form, empty_revision_form())
         |> assign(:show_revision_form, false)
         |> assign_database_details(organization_id, mission.mission_id, catalog_database_id)
         |> allow_upload(:artifact,
           accept: :any,
           max_entries: 1,
           max_file_size: 50 * 1024 * 1024
         )}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Catalog database not found.")
         |> redirect(to: ~p"/missions/#{mission.mission_id}/catalog")}
    end
  end

  @impl true
  def handle_info({event, run}, socket)
      when event in [
             :import_run_started,
             :import_run_updated,
             :import_run_completed,
             :import_run_failed
           ] do
    if run.catalog_database_id == socket.assigns.database.catalog_database_id do
      mission = socket.assigns.current_mission
      organization_id = socket.assigns.current_scope.organization_id

      {:noreply,
       assign_database_details(
         socket,
         organization_id,
         mission.mission_id,
         socket.assigns.database.catalog_database_id
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_revision_form", _params, socket) do
    toggled = !socket.assigns.show_revision_form

    socket =
      if toggled do
        socket
      else
        socket
        |> cancel_active_uploads(:artifact)
        |> assign(:revision_form, empty_revision_form())
      end

    {:noreply, assign(socket, :show_revision_form, toggled)}
  end

  @impl true
  def handle_event("validate", %{"catalog_revision" => params}, socket) do
    {:noreply, assign(socket, :revision_form, to_form(params, as: :catalog_revision))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :artifact, ref)}
  end

  def handle_event("save", params, socket) do
    form_params = Map.get(params, "catalog_revision", %{})

    case detect_importer_from_entries(socket.assigns.uploads.artifact.entries) do
      {:ok, %{descriptor: descriptor}} ->
        perform_revision_upload(socket, descriptor, form_params)

      _ ->
        {:noreply,
         put_flash(socket, :error, "Pick a file with a supported format before uploading.")}
    end
  end

  defp perform_revision_upload(socket, descriptor, form_params) do
    database = socket.assigns.database
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    uploaded_by = uploader_identity(socket)

    [artifact_or_error | _] =
      consume_uploaded_entries(socket, :artifact, fn %{path: path}, entry ->
        case File.read(path) do
          {:ok, bytes} ->
            upload = %{filename: entry.client_name, bytes: bytes, client_type: entry.client_type}

            {:ok,
             Artifact.build_from_upload(mission.mission_id, descriptor, upload,
               uploaded_by: uploaded_by,
               catalog_database_id: database.catalog_database_id
             )}

          {:error, reason} ->
            {:ok, {:error, {:file_read_failed, reason}}}
        end
      end)

    case artifact_or_error do
      %Artifact{} = artifact ->
        case Catalog.start_revision_import(
               organization_id,
               mission.mission_id,
               database.catalog_database_id,
               artifact,
               descriptor.importer_key,
               requested_by: uploaded_by,
               importer_version: descriptor.version,
               metadata:
                 revision_metadata(form_params, next_revision_label(socket.assigns.revisions))
             ) do
          {:ok, run} ->
            {:noreply,
             push_navigate(socket,
               to: ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}"
             )}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to start revision import: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to read uploaded file: #{inspect(reason)}")}
    end
  end

  defp assign_database_details(socket, organization_id, mission_id, catalog_database_id) do
    revisions = Catalog.list_revisions(organization_id, mission_id, catalog_database_id)

    artifacts =
      Catalog.list_artifacts(organization_id, mission_id,
        catalog_database_id: catalog_database_id
      )

    runs =
      Catalog.list_import_runs(organization_id, mission_id,
        catalog_database_id: catalog_database_id
      )

    socket
    |> assign(:revisions, revisions)
    |> assign(:artifacts, artifacts)
    |> assign(:runs, runs)
    |> assign(:revision_rows, Enum.map(revisions, &revision_dto(&1, mission_id)))
    |> assign(:import_run_rows, Enum.map(runs, &import_run_dto(&1, mission_id)))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="catalog-database-show-page">
        <form
          :if={@show_revision_form}
          id="catalog-revision-upload-live-form"
          phx-change="validate"
          phx-submit="save"
          style="display: none"
        >
          <.live_file_input upload={@uploads.artifact} />
        </form>

        <.vue
          id="catalog-database-show-component"
          v-component="FederatedFullPageSurface"
          application_key="mission_catalog"
          surface_id="catalog_database_show"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id, catalog_database_id: @database.catalog_database_id}}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp database_details_dto(database) do
    %{
      id: database.catalog_database_id,
      name: database.name,
      slug: database.slug,
      description: database.description || @default_database_description,
      runtime_usage_summary: "No runtime bindings yet."
    }
  end

  defp navigation_dto(mission, database) do
    %{
      mission: %{
        label: mission.display_name,
        href: ~p"/missions/#{mission.mission_id}"
      },
      catalog: %{
        label: "Catalog",
        href: ~p"/missions/#{mission.mission_id}/catalog"
      },
      current: %{label: database.name}
    }
  end

  defp revision_dto(revision, mission_id) do
    %{
      id: "catalog-revision-row-#{revision.catalog_revision_id}",
      revision_id: revision.catalog_revision_id,
      label: revision.revision_label,
      number: revision.revision_number,
      mission_model_revision_id: revision.mission_model_revision_id,
      href: ~p"/missions/#{mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
    }
  end

  defp import_run_dto(run, mission_id) do
    %{
      id: "catalog-import-run-row-#{run.import_run_id}",
      run_id: run.import_run_id,
      status: import_status_dto(run.status),
      href: ~p"/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
    }
  end

  defp import_status_dto(status) do
    %{
      value: Atom.to_string(status),
      label: import_status_label(status),
      tone: import_status_tone(status)
    }
  end

  defp import_status_label(:running), do: "Running"
  defp import_status_label(:completed), do: "Completed"
  defp import_status_label(:failed), do: "Failed"
  defp import_status_label(status), do: status |> to_string() |> String.capitalize()

  defp import_status_tone(:completed), do: "ready"
  defp import_status_tone(:failed), do: "blocked"
  defp import_status_tone(_status), do: "info"

  defp revision_metadata(form_params, fallback_label) do
    %{
      "revision_label" => normalize(form_params["revision_label"]) || fallback_label,
      "revision_notes" => normalize(form_params["revision_notes"]) || ""
    }
  end

  defp next_revision_label(revisions), do: "Revision #{length(revisions) + 1}"

  defp empty_revision_form do
    to_form(%{"revision_label" => "", "revision_notes" => ""}, as: :catalog_revision)
  end

  defp revision_upload_form_dto(form) do
    %{
      id: "catalog-revision-upload-form",
      name: "catalog_revision",
      class: "space-y-4",
      card: %{
        id: "catalog-revision-upload-card",
        class: "card bg-base-200 border border-base-300",
        body_class: "card-body p-6",
        title: "Add revision",
        title_class: "hud-label"
      },
      content_class: nil,
      description: nil,
      primary_fields_class: "grid grid-cols-1 md:grid-cols-2 gap-4",
      primary_fields: [
        upload_field_dto(
          "catalog_revision",
          "revision_label",
          "text",
          "Revision label",
          form.params
        ),
        upload_field_dto(
          "catalog_revision",
          "revision_notes",
          "text",
          "Notes",
          form.params
        )
      ],
      secondary_fields: [],
      file_input: %{
        id: "catalog-revision-upload-file-input",
        name: "artifact",
        class: "file-input file-input-bordered w-full",
        wrapper_class: nil
      },
      entries: upload_entries_presentation(),
      error_class: "border px-4 py-3 text-sm text-base-content border-error/40 bg-error/10",
      importer: importer_presentation(),
      actions_class: nil,
      submit: %{
        id: "catalog-revision-upload-submit",
        label: "Upload revision",
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

  defp uploader_identity(socket) do
    case socket.assigns.current_scope do
      %{user: %{id: id, email: email}} -> %{user_id: id, email: email}
      %{user: %{email: email}} -> %{email: email}
      _ -> %{}
    end
  end

  defp cancel_active_uploads(socket, name) do
    socket.assigns.uploads
    |> Map.get(name)
    |> case do
      nil ->
        socket

      upload ->
        Enum.reduce(upload.entries, socket, fn entry, acc ->
          cancel_upload(acc, name, entry.ref)
        end)
    end
  end

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_other), do: nil
end
