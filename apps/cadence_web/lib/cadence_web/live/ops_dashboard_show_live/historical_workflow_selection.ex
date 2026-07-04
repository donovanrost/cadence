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

  def event_query(event_id) do
    SelectionQuery.new(%{
      "selected_target" => "telemetry_backfill_lifecycle_event",
      "selected_id" => event_id
    })
  end

  def event_selection(event, params \\ %{}) when is_map(event) and is_map(params) do
    %HistoricalWorkflowSelectionResult{
      event: event,
      query: event_query(Map.fetch!(event, :backfill_lifecycle_event_id)),
      link: event_link(event, params)
    }
  end

  def retry_selection(%{events: [event | _events]}, _fallback_event_id) do
    event_selection(event)
  end

  def retry_selection(_summary, fallback_event_id) do
    %HistoricalWorkflowSelectionResult{
      query: event_query(fallback_event_id),
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

  defp param(params, legacy_key, form_key) do
    Map.get(params, legacy_key) || Map.get(params, form_key)
  end
end
