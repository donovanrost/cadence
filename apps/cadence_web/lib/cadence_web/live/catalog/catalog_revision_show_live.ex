defmodule CadenceWeb.CatalogRevisionShowLive do
  @moduledoc false

  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog

  @impl true
  def mount(%{"catalog_revision_id" => catalog_revision_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    case Catalog.fetch_revision(organization_id, mission.mission_id, catalog_revision_id) do
      {:ok, revision} ->
        {:ok,
         socket
         |> assign(:page_title, revision.revision_label)
         |> assign(:nav_item, :catalog)
         |> assign(:revision, revision)
         |> assign_revision_context(organization_id, mission.mission_id, revision)}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Catalog revision not found.")
         |> redirect(to: ~p"/missions/#{mission.mission_id}/catalog")}
    end
  end

  defp assign_revision_context(socket, organization_id, mission_id, revision) do
    database =
      fetch_optional(fn ->
        Catalog.fetch_database(organization_id, mission_id, revision.catalog_database_id)
      end)

    artifact =
      fetch_optional(fn ->
        Catalog.fetch_artifact(organization_id, mission_id, revision.artifact_id)
      end)

    import_run =
      fetch_optional(fn ->
        Catalog.fetch_import_run(organization_id, mission_id, revision.import_run_id)
      end)

    telemetry_snapshot =
      fetch_snapshot(organization_id, mission_id, revision.telemetry_snapshot_id, :telemetry)

    command_snapshot =
      fetch_snapshot(organization_id, mission_id, revision.command_snapshot_id, :command)

    socket
    |> assign(:database, database)
    |> assign(:artifact, artifact)
    |> assign(:import_run, import_run)
    |> assign(:telemetry_snapshot, telemetry_snapshot)
    |> assign(:command_snapshot, command_snapshot)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title={@revision.revision_label}
        breadcrumbs={revision_breadcrumb_items(assigns)}
      >
        <:title_suffix>Revision {@revision.revision_number}</:title_suffix>
      </.page_header>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <.card title="Revision provenance" class="lg:col-span-2">
          <div class="divide-y divide-base-300 mt-3">
            <.detail_row label="Database" value={@database && @database.name} />
            <.detail_row label="Artifact">
              <.maybe_artifact_link current_mission={@current_mission} artifact={@artifact} />
            </.detail_row>
            <.detail_row label="Import run">
              <.maybe_run_link current_mission={@current_mission} run={@import_run} />
            </.detail_row>
            <.detail_row label="Content SHA-256">
              <span class="font-mono text-xs break-all">{@revision.content_sha256}</span>
            </.detail_row>
          </div>
        </.card>

        <.card title="Runtime usage">
          <p class="text-sm text-base-content/60 mt-2" id="catalog-runtime-usage-summary">
            No runtime bindings yet.
          </p>
          <.button variant={:ghost} class="mt-3" disabled>
            Use this revision in runtime
          </.button>
        </.card>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <.telemetry_snapshot_card current_mission={@current_mission} snapshot={@telemetry_snapshot} />
        <.command_snapshot_card current_mission={@current_mission} snapshot={@command_snapshot} />
      </div>
    </div>
    """
  end

  attr :current_mission, :map, required: true
  attr :artifact, :map, default: nil

  defp maybe_artifact_link(%{artifact: nil} = assigns) do
    ~H"""
    <span>—</span>
    """
  end

  defp maybe_artifact_link(assigns) do
    ~H"""
    <.link
      navigate={
        ~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{@artifact.artifact_id}"
      }
      class="hover:underline"
    >
      {@artifact.artifact_name}
    </.link>
    """
  end

  attr :current_mission, :map, required: true
  attr :run, :map, default: nil

  defp maybe_run_link(%{run: nil} = assigns) do
    ~H"""
    <span>—</span>
    """
  end

  defp maybe_run_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@run.import_run_id}"}
      class="font-mono hover:underline"
    >
      {@run.import_run_id}
    </.link>
    """
  end

  attr :current_mission, :map, required: true
  attr :snapshot, :map, default: nil

  defp telemetry_snapshot_card(%{snapshot: nil} = assigns) do
    ~H"""
    <.card title="Telemetry snapshot">
      <.empty_state compact title="No telemetry snapshot in this revision." class="mt-2" />
    </.card>
    """
  end

  defp telemetry_snapshot_card(assigns) do
    ~H"""
    <.snapshot_summary_card
      title="Telemetry snapshot"
      icon="hero-signal"
      counts={[
        {"Packets", length(@snapshot.packets)},
        {"Points", length(@snapshot.points)},
        {"Types", length(@snapshot.types)},
        {"Units", length(@snapshot.units)}
      ]}
      navigate={
        ~p"/missions/#{@current_mission.mission_id}/catalog/telemetry_snapshots/#{@snapshot.snapshot_id}"
      }
    />
    """
  end

  attr :current_mission, :map, required: true
  attr :snapshot, :map, default: nil

  defp command_snapshot_card(%{snapshot: nil} = assigns) do
    ~H"""
    <.card title="Command snapshot">
      <.empty_state compact title="No command snapshot in this revision." class="mt-2" />
    </.card>
    """
  end

  defp command_snapshot_card(assigns) do
    ~H"""
    <.snapshot_summary_card
      title="Command snapshot"
      icon="hero-command-line"
      counts={[
        {"Commands", length(@snapshot.command_definitions)},
        {"Arguments", length(@snapshot.arguments)},
        {"Argument types", length(@snapshot.argument_types)},
        {"Layouts", length(@snapshot.encoding_layouts)}
      ]}
      navigate={
        ~p"/missions/#{@current_mission.mission_id}/catalog/command_snapshots/#{@snapshot.snapshot_id}"
      }
    />
    """
  end

  defp fetch_optional(fun) when is_function(fun, 0) do
    case fun.() do
      {:ok, value} -> value
      {:error, _reason} -> nil
    end
  end

  defp fetch_snapshot(_organization_id, _mission_id, nil, _family), do: nil

  defp fetch_snapshot(organization_id, mission_id, snapshot_id, :telemetry) do
    fetch_optional(fn ->
      Catalog.fetch_telemetry_snapshot(organization_id, mission_id, snapshot_id)
    end)
  end

  defp fetch_snapshot(organization_id, mission_id, snapshot_id, :command) do
    fetch_optional(fn ->
      Catalog.fetch_command_snapshot(organization_id, mission_id, snapshot_id)
    end)
  end

  defp revision_breadcrumb_items(%{current_mission: mission, database: nil, revision: revision}) do
    [
      {mission.display_name, ~p"/missions/#{mission.mission_id}"},
      {"Catalog", ~p"/missions/#{mission.mission_id}/catalog"},
      {revision.revision_label, nil}
    ]
  end

  defp revision_breadcrumb_items(%{
         current_mission: mission,
         database: database,
         revision: revision
       }) do
    [
      {mission.display_name, ~p"/missions/#{mission.mission_id}"},
      {"Catalog", ~p"/missions/#{mission.mission_id}/catalog"},
      {database.name,
       ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"},
      {revision.revision_label, nil}
    ]
  end
end
