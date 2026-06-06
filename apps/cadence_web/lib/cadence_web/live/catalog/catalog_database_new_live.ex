defmodule CadenceWeb.CatalogDatabaseNewLive do
  @moduledoc false

  # Authz note: any signed-in mission member can create a catalog database.
  # Tighten once platform-wide authorization is defined.
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New catalog database")
     |> assign(:nav_item, :catalog)
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
    <div class="space-y-6 max-w-2xl">
      <div>
        <.breadcrumbs items={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Catalog", ~p"/missions/#{@current_mission.mission_id}/catalog"},
          {"New database", nil}
        ]} />
        <h1 class="text-2xl font-bold text-base-content mt-2">New catalog database</h1>
      </div>

      <.upload_card uploads={@uploads} form={@database_form} />

      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
          class="btn btn-ghost"
        >
          Cancel
        </.link>
      </div>
    </div>
    """
  end
end
