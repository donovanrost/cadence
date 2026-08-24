defmodule CadenceWeb.CatalogImportRunShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

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
          |> assign(:navigation, navigation_dto(mission, run))
          |> assign_import_run(run)

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
      {:noreply, assign_import_run(socket, run)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="catalog-import-run-show-page">
        <.vue
          id="catalog-import-run-show-component"
          v-component="CatalogImportRunShow"
          navigation={@navigation}
          status={@status}
          run_details={@run_details}
          mission_model={@mission_model}
          diagnostic_groups={@diagnostic_groups}
          failure_reason={@failure_reason}
          v-ssr={false}
        />
      </div>
    </Layouts.app>
    """
  end

  defp assign_import_run(socket, run) do
    socket
    |> assign(:run, run)
    |> assign(:status, status_dto(run.status))
    |> assign(:run_details, run_details_dto(run))
    |> assign(:mission_model, mission_model_dto(run))
    |> assign(:diagnostic_groups, diagnostic_groups_dto(run.diagnostics))
    |> assign(:failure_reason, failure_reason_dto(run))
  end

  defp navigation_dto(mission, run) do
    %{
      breadcrumbs: [
        %{
          label: mission.display_name,
          href: ~p"/missions/#{mission.mission_id}"
        },
        %{
          label: "Catalog",
          href: ~p"/missions/#{mission.mission_id}/catalog"
        },
        %{
          label: "Artifact",
          href: ~p"/missions/#{mission.mission_id}/catalog/artifacts/#{run.artifact_id}"
        },
        %{label: "Import run", href: nil}
      ]
    }
  end

  defp status_dto(status) do
    %{
      label: status_label(status),
      tone: status_tone(status)
    }
  end

  defp status_label(:running), do: "Running"
  defp status_label(:completed), do: "Completed"
  defp status_label(:failed), do: "Failed"
  defp status_label(status), do: status |> to_string() |> String.capitalize()

  defp status_tone(:completed), do: "ready"
  defp status_tone(:failed), do: "blocked"
  defp status_tone(_status), do: "info"

  defp run_details_dto(run) do
    %{
      importer: %{
        id: "catalog-importer-version",
        label: "#{run.importer_key} v#{run.importer_version}"
      },
      started_at: format_timestamp(run.started_at),
      completed_at: format_timestamp(run.completed_at)
    }
  end

  defp format_timestamp(nil), do: nil
  defp format_timestamp(timestamp), do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")

  defp mission_model_dto(run) do
    case mission_model_summary(run) do
      nil ->
        nil

      summary ->
        %{
          id: "catalog-import-mission-model",
          revision_id: summary["revision_id"],
          declaration_count: summary["declaration_count"],
          plan_count: map_size(summary["plans"] || %{})
        }
    end
  end

  defp diagnostic_groups_dto(diagnostics) do
    [:error, :warning, :info]
    |> Enum.flat_map(fn severity ->
      items = Enum.filter(diagnostics, &(&1.severity == severity))

      if items == [] do
        []
      else
        [
          %{
            title: "#{severity_heading(severity)} (#{length(items)})",
            items: Enum.map(items, &diagnostic_dto/1)
          }
        ]
      end
    end)
  end

  defp diagnostic_dto(diagnostic) do
    %{
      code: diagnostic.code,
      message: diagnostic.message,
      detail: diagnostic_detail(diagnostic),
      path: diagnostic_path(diagnostic.path)
    }
  end

  defp severity_heading(:error), do: "Errors"
  defp severity_heading(:warning), do: "Warnings"
  defp severity_heading(:info), do: "Info"

  defp diagnostic_detail(diagnostic) do
    metadata = Map.get(diagnostic, :metadata, %{}) || %{}

    [
      metadata_value(metadata, "consumption_summary", "Built-in telemetry"),
      metadata_value(metadata, "consumption_status", "Status"),
      metadata_value(metadata, "packet_name", "Packet"),
      metadata_value(metadata, "entry_name", "Entry"),
      metadata_value(metadata, "point_name", "Point"),
      metadata_value(metadata, "type_name", "Type"),
      metadata_value(metadata, "base_type", "Base type"),
      metadata_value(metadata, "point_id", "Point ID"),
      metadata_value(metadata, "type_id", "Type ID")
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " | ")
    end
  end

  defp metadata_value(metadata, key, label) do
    case Map.get(metadata, key) do
      value when is_binary(value) and value != "" -> "#{label}: #{value}"
      _ -> nil
    end
  end

  defp diagnostic_path([]), do: nil
  defp diagnostic_path(path), do: Enum.join(path, " / ")

  defp failure_reason_dto(%{status: :failed, failure_reason: reason}) do
    format_failure_reason(reason)
  end

  defp failure_reason_dto(_run), do: nil

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
