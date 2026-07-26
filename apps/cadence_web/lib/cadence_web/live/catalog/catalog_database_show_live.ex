defmodule CadenceWeb.CatalogDatabaseShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact
  alias Cadence.Catalog.Events

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
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title={@database.name}
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Catalog", ~p"/missions/#{@current_mission.mission_id}/catalog"},
          {@database.name, nil}
        ]}
      >
        <:title_suffix>{@database.slug}</:title_suffix>
        <:actions>
          <.button
            id="add-revision-toggle"
            variant={if @show_revision_form, do: :ghost, else: :primary}
            size={:md}
            phx-click="toggle_revision_form"
          >
            {if @show_revision_form, do: "Cancel", else: "+ Add revision"}
          </.button>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <.card title="Database" class="lg:col-span-2">
          <p class="text-sm text-base-content/70 mt-2">
            {@database.description ||
              "Mission catalog library entry. Add immutable revisions here, then choose runtime usage separately."}
          </p>
        </.card>
        <.card title="Runtime usage">
          <p class="text-sm text-base-content/60 mt-2" id="catalog-runtime-usage-summary">
            No runtime bindings yet.
          </p>
        </.card>
      </div>

      <.revision_upload_card :if={@show_revision_form} uploads={@uploads} form={@revision_form} />

      <.revision_history current_mission={@current_mission} revisions={@revisions} />

      <.import_attempts current_mission={@current_mission} runs={@runs} />
    </div>
    """
  end

  attr :uploads, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true

  defp revision_upload_card(assigns) do
    assigns =
      assign(
        assigns,
        :detected_importer,
        detect_importer_from_entries(assigns.uploads.artifact.entries)
      )

    ~H"""
    <.card title="Add revision">
      <.form
        id="catalog-revision-upload-form"
        for={@form}
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.input field={@form[:revision_label]} type="text" label="Revision label" />
          <.input field={@form[:revision_notes]} type="text" label="Notes" />
        </div>
        <.live_file_input upload={@uploads.artifact} class="file-input file-input-bordered w-full" />
        <.detected_preview detected={@detected_importer} />
        <.button type="submit" size={:md} disabled={!importer_detected?(@detected_importer)}>
          Upload revision
        </.button>
      </.form>
    </.card>
    """
  end

  attr :current_mission, :map, required: true
  attr :revisions, :list, required: true

  defp revision_history(assigns) do
    ~H"""
    <.card id="catalog-revision-history" title="Revision history">
      <%= if @revisions == [] do %>
        <.empty_state compact title="No revisions yet." />
      <% else %>
        <.table id="catalog-revisions-table" rows={@revisions} row_accent={false}>
          <:col :let={revision} label="Revision">
            <p class="font-medium">{revision.revision_label}</p>
            <p class="font-mono text-xs text-base-content/60">
              {"#" <> Integer.to_string(revision.revision_number)}
            </p>
          </:col>
          <:col :let={revision} label="Telemetry">
            {if revision.telemetry_snapshot_id, do: "Present", else: "—"}
          </:col>
          <:col :let={revision} label="Command">
            {if revision.command_snapshot_id, do: "Present", else: "—"}
          </:col>
          <:col :let={revision} label="Actions" align={:right}>
            <.button
              variant={:ghost}
              size={:xs}
              navigate={
                ~p"/missions/#{@current_mission.mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
              }
            >
              View revision
            </.button>
          </:col>
        </.table>
      <% end %>
    </.card>
    """
  end

  attr :current_mission, :map, required: true
  attr :runs, :list, required: true

  defp import_attempts(assigns) do
    ~H"""
    <.card id="catalog-import-attempts" title="Import attempts">
      <%= if @runs == [] do %>
        <.empty_state compact title="No import attempts yet." />
      <% else %>
        <.table id="catalog-import-runs-table" rows={@runs} row_accent={false}>
          <:col :let={run} label="Status"><.import_run_status_badge status={run.status} /></:col>
          <:col :let={run} label="Run" class="font-mono text-xs text-base-content/60">
            {run.import_run_id}
          </:col>
          <:col :let={run} label="Actions" align={:right}>
            <.button
              variant={:ghost}
              size={:xs}
              navigate={
                ~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{run.import_run_id}"
              }
            >
              View run
            </.button>
          </:col>
        </.table>
      <% end %>
    </.card>
    """
  end

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
