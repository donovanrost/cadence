defmodule CadenceWeb.OpsDashboardShowLive.HistoricalWorkflowSelection do
  @moduledoc false

  alias Cadence.Dashboards.DataLink

  alias CadenceWeb.OpsDashboardShowLive.{
    HistoricalWorkflowParams,
    HistoricalWorkflowSelectionResult,
    SelectionQuery
  }

  def event_link(event, params \\ %{})

  def event_link(event_id, _params) when is_binary(event_id) do
    %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: event_id,
      context: %{logical_source: :events},
      source: :frame
    }
  end

  def event_link(event, params) when is_map(event) and is_map(params) do
    params = HistoricalWorkflowParams.to_event_params(params)

    %DataLink{
      label: "Telemetry backfill lifecycle event",
      target: :telemetry_backfill_lifecycle_event,
      target_id: Map.fetch!(event, :backfill_lifecycle_event_id),
      context: %{
        logical_source: :events,
        observable_id:
          Map.get(event, :observable_id) || Map.get(event, :point_id) ||
            param(params, "point-id", "point_id"),
        data: %{
          realm: Map.get(event, :realm) || Map.get(params, "realm"),
          data_source_id:
            Map.get(event, :data_source_id) || param(params, "data-source-id", "data_source_id"),
          source_binding_id:
            Map.get(event, :binding_id) || param(params, "source-binding-id", "source_binding_id")
        }
      },
      source: :frame
    }
  end

  def event_query(event_id, params \\ %{}) do
    params = HistoricalWorkflowParams.to_event_params(params)

    %{
      "selected_target" => "telemetry_backfill_lifecycle_event",
      "selected_id" => event_id,
      "time_mode" => param(params, "time-mode", "time_mode", "dashboard_time_mode"),
      "replay_run_id" =>
        param(params, "replay-run-id", "replay_run_id", "dashboard_replay_run_id"),
      "selected_data_view" =>
        param(params, "data-view", "data_view", "dashboard_data_view") ||
          param(params, "selected-data-view", "selected_data_view"),
      "limit_mode" => param(params, "limit-mode", "limit_mode", "dashboard_limit_mode")
    }
    |> SelectionQuery.new()
  end

  def event_selection(event, params \\ %{}) when is_map(event) and is_map(params) do
    %HistoricalWorkflowSelectionResult{
      event: event,
      query: event_query(Map.fetch!(event, :backfill_lifecycle_event_id), params),
      link: event_link(event, params)
    }
  end

  def retry_selection(summary, fallback_event_id, params \\ %{})

  def retry_selection(%{events: [event | _events]}, _fallback_event_id, params) do
    event_selection(event, params)
  end

  def retry_selection(_summary, fallback_event_id, params) do
    %HistoricalWorkflowSelectionResult{
      query: event_query(fallback_event_id, params),
      link: event_link(fallback_event_id)
    }
  end

  def group_transition_selection(events, job_results, params \\ %{})

  def group_transition_selection([_event | _events] = events, job_results, params)
      when is_list(job_results) and is_map(params) do
    event =
      events
      |> Enum.zip(job_results)
      |> Enum.find_value(fn
        {event, {:error, _reason}} -> event
        {_event, _job_result} -> nil
      end) || List.first(events)

    event_selection(event, params)
  end

  def group_transition_selection([event | _events], _job_results, params) when is_map(params) do
    event_selection(event, params)
  end

  defp param(params, legacy_key, form_key, context_key \\ nil) do
    Map.get(params, legacy_key) ||
      Map.get(params, form_key) ||
      Map.get(params, context_key) ||
      Map.get(params, atom_key(context_key)) ||
      Map.get(params, atom_key(form_key))
  end

  defp atom_key("dashboard_time_mode"), do: :dashboard_time_mode
  defp atom_key("dashboard_replay_run_id"), do: :dashboard_replay_run_id
  defp atom_key("dashboard_data_view"), do: :dashboard_data_view
  defp atom_key("dashboard_limit_mode"), do: :dashboard_limit_mode
  defp atom_key("time_mode"), do: :time_mode
  defp atom_key("replay_run_id"), do: :replay_run_id
  defp atom_key("data_view"), do: :data_view
  defp atom_key("selected_data_view"), do: :selected_data_view
  defp atom_key("limit_mode"), do: :limit_mode
  defp atom_key(_key), do: nil
end
