defmodule CadenceWeb.CatalogIndexLive do
  @moduledoc false

  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Events

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    if connected?(socket), do: Events.subscribe_import_runs(mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Catalog")
     |> assign(:nav_item, :catalog)
     |> assign(:database_form, empty_database_form())
     |> assign_databases(organization_id, mission.mission_id)
     |> allow_upload(:artifact,
       accept: :any,
       max_entries: 1,
       max_file_size: 50 * 1024 * 1024
     )}
  end

  @impl true
  def handle_info({event, _run}, socket)
      when event in [
             :import_run_started,
             :import_run_updated,
             :import_run_completed,
             :import_run_failed
           ] do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    {:noreply, assign_databases(socket, organization_id, mission.mission_id)}
  end

  @impl true
  def handle_event("validate", %{"catalog_database" => params}, socket) do
    {:noreply, assign(socket, :database_form, to_form(params, as: :catalog_database))}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :artifact, ref)}
  end

  def handle_event("save", params, socket) do
    form_params = Map.get(params, "catalog_database", %{})

    case detect_from_uploads(socket) do
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

  defp detect_from_uploads(socket) do
    detect_importer_from_entries(socket.assigns.uploads.artifact.entries)
  end

  defp uploader_identity(socket) do
    case socket.assigns.current_scope do
      %{user: %{id: id, email: email}} -> %{user_id: id, email: email}
      %{user: %{email: email}} -> %{email: email}
      _ -> %{}
    end
  end

  defp assign_databases(socket, organization_id, mission_id) do
    databases = Catalog.list_databases(organization_id, mission_id)
    latest_revisions = Catalog.latest_revision_by_database(organization_id, mission_id)
    latest_runs = Catalog.latest_import_run_by_database(organization_id, mission_id)

    socket
    |> assign(:databases, databases)
    |> assign(:latest_revisions, latest_revisions)
    |> assign(:latest_runs, latest_runs)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Catalog</h1>
          <p class="text-sm text-base-content/60 mt-1">
            Mission database library. Revisions are imported here; runtime usage is selected later.
          </p>
        </div>
      </div>

      <.upload_card uploads={@uploads} form={@database_form} />

      <.databases_table
        current_mission={@current_mission}
        databases={@databases}
        latest_revisions={@latest_revisions}
        latest_runs={@latest_runs}
      />
    </div>
    """
  end

  attr :current_mission, :map, required: true
  attr :databases, :list, required: true
  attr :latest_revisions, :map, required: true
  attr :latest_runs, :map, required: true

  defp databases_table(assigns) do
    ~H"""
    <%= if @databases == [] do %>
      <div class="card bg-base-200" id="catalog-database-list">
        <div class="card-body p-6 text-center">
          <p class="hud-label text-base-content/60">No catalog databases yet</p>
          <p class="text-sm text-base-content/50 mt-1">
            Upload a command and telemetry database to create the first immutable revision.
          </p>
        </div>
      </div>
    <% else %>
      <div class="card bg-base-200" id="catalog-database-list">
        <table class="table">
          <thead>
            <tr>
              <th class="hud-label">Database</th>
              <th class="hud-label">Family</th>
              <th class="hud-label">Latest revision</th>
              <th class="hud-label">Latest import</th>
              <th class="hud-label">Runtime usage</th>
              <th class="hud-label text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={database <- @databases}>
              <td>
                <.link
                  navigate={
                    ~p"/missions/#{@current_mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
                  }
                  class="font-medium hover:underline"
                >
                  {database.name}
                </.link>
                <p class="font-mono text-xs text-base-content/50">{database.slug}</p>
              </td>
              <td><.catalog_family_badge family={database.catalog_family} /></td>
              <td>
                <.latest_revision_cell
                  revision={Map.get(@latest_revisions, database.catalog_database_id)}
                  current_mission={@current_mission}
                />
              </td>
              <td>
                <.latest_run_cell
                  run={Map.get(@latest_runs, database.catalog_database_id)}
                  current_mission={@current_mission}
                />
              </td>
              <td>
                <span class="badge badge-ghost badge-sm" id="catalog-runtime-usage-summary">
                  No runtime bindings yet
                </span>
              </td>
              <td class="text-right">
                <.action_menu>
                  <:action>
                    <.link navigate={
                      ~p"/missions/#{@current_mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
                    }>
                      View database
                    </.link>
                  </:action>
                </.action_menu>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    <% end %>
    """
  end

  attr :revision, :map, default: nil
  attr :current_mission, :map, required: true

  defp latest_revision_cell(%{revision: nil} = assigns) do
    ~H"""
    <span class="text-base-content/40 text-xs">No revisions</span>
    """
  end

  defp latest_revision_cell(assigns) do
    ~H"""
    <.link
      navigate={
        ~p"/missions/#{@current_mission.mission_id}/catalog/revisions/#{@revision.catalog_revision_id}"
      }
      class="font-mono text-sm hover:underline"
    >
      {@revision.revision_label}
    </.link>
    """
  end

  attr :run, :map, default: nil
  attr :current_mission, :map, required: true

  defp latest_run_cell(%{run: nil} = assigns) do
    ~H"""
    <span class="text-base-content/40 text-xs">—</span>
    """
  end

  defp latest_run_cell(assigns) do
    ~H"""
    <.link
      navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@run.import_run_id}"}
      class="inline-flex"
    >
      <.import_run_status_badge status={@run.status} />
    </.link>
    """
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
end
