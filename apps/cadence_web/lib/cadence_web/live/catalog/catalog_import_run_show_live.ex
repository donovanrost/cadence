defmodule CadenceWeb.CatalogImportRunShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Events

  @impl true
  def mount(%{"import_run_id" => import_run_id}, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    case Catalog.fetch_import_run(organization_id, mission.mission_id, import_run_id) do
      {:ok, run} ->
        if connected?(socket),
          do: Events.subscribe_import_run(mission.mission_id, run.import_run_id)

        socket =
          socket
          |> assign(:page_title, "Import run")
          |> assign(:nav_item, :catalog)
          |> assign(:run, run)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Import run not found.")
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
    if run.import_run_id == socket.assigns.run.import_run_id do
      {:noreply, assign(socket, :run, run)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title="Import run"
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Catalog", ~p"/missions/#{@current_mission.mission_id}/catalog"},
          {"Artifact",
           ~p"/missions/#{@current_mission.mission_id}/catalog/artifacts/#{@run.artifact_id}"},
          {"Import run", nil}
        ]}
      >
        <:title_suffix><.import_run_status_badge status={@run.status} /></:title_suffix>
      </.page_header>

      <.run_header run={@run} />

      <.mission_model_summary_card
        :if={mission_model_summary(@run)}
        summary={mission_model_summary(@run)}
      />

      <.diagnostic_list diagnostics={@run.diagnostics} />

      <.failure_block :if={@run.status == :failed} failure_reason={@run.failure_reason} />

    </div>
    """
  end

  attr :run, :map, required: true

  defp run_header(assigns) do
    ~H"""
    <.card>
      <div class="text-sm space-y-1">
        <div class="flex items-center gap-2">
          <span class="text-base-content/60">Importer</span>
          <span id="catalog-importer-version" class="font-mono">
            {@run.importer_key} v{@run.importer_version}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-base-content/60">Started</span>
          <span>{Calendar.strftime(@run.started_at, "%Y-%m-%d %H:%M:%S UTC")}</span>
        </div>
        <div :if={@run.completed_at} class="flex items-center gap-2">
          <span class="text-base-content/60">Completed</span>
          <span>{Calendar.strftime(@run.completed_at, "%Y-%m-%d %H:%M:%S UTC")}</span>
        </div>
      </div>
    </.card>
    """
  end

  attr :summary, :map, required: true

  defp mission_model_summary_card(assigns) do
    ~H"""
    <.card id="catalog-import-mission-model" title="Mission Model">
      <div class="divide-y divide-base-300">
        <.detail_row label="Revision" mono>
          {@summary["revision_id"]}
        </.detail_row>
        <.detail_row label="Declarations" mono>
          {@summary["declaration_count"]}
        </.detail_row>
        <.detail_row label="Plans" mono>
          {map_size(@summary["plans"] || %{})}
        </.detail_row>
      </div>
    </.card>
    """
  end

  attr :failure_reason, :any, required: true

  defp failure_block(assigns) do
    ~H"""
    <.callout variant={:error}>
      <p class="font-mono text-sm">{format_failure_reason(@failure_reason)}</p>
    </.callout>
    """
  end

  defp format_failure_reason({:exception, message}) when is_binary(message), do: message

  defp format_failure_reason({:job_enqueue_failed, reason}),
    do: "Job enqueue failed: #{inspect(reason)}"

  defp format_failure_reason({kind, reason}) when is_atom(kind), do: "#{kind}: #{inspect(reason)}"
  defp format_failure_reason(reason), do: inspect(reason)

  defp mission_model_summary(%{result_document: %{"mission_model" => summary}})
       when is_map(summary),
       do: summary

  defp mission_model_summary(_run), do: nil
end
