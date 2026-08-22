defmodule CadenceWeb.OpsDataOperationsLive.Presentation do
  @moduledoc false

  alias Cadence.Telemetry.DataManagement.WorkflowEventEvidence
  alias Cadence.Telemetry.Storage.BackfillLifecycleGroup

  @spec build([map()]) :: [map()]
  def build(events) when is_list(events) do
    events
    |> Enum.group_by(&group_id/1)
    |> Enum.map(fn {group_id, group_events} -> group(group_id, group_events, events) end)
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
  end

  @spec group_id(map()) :: binary()
  def group_id(event) do
    BackfillLifecycleGroup.payload_value(event, :request_group_id) ||
      Map.get(event, :backfill_run_id) || Map.get(event, :backfill_lifecycle_event_id)
  end

  defp group(group_id, events, all_events) do
    events = Enum.sort_by(events, &event_sort_key/1)
    latest = List.last(events)
    summary = BackfillLifecycleGroup.summary(events, all_events)

    %{
      id: group_id,
      dom_id: "data-operation-#{group_id}",
      workflow: workflow(latest),
      state: summary.state,
      terminal?: summary.terminal?,
      progress: summary.progress,
      size: summary.size,
      requested: summary.requested,
      approved: summary.approved,
      started: summary.started,
      completed: summary.completed,
      failed: summary.failed,
      resolved_failed: summary.resolved_failed,
      retryable_failed: summary.retryable_failed,
      correction_requested: summary.correction_requested,
      correction_started: summary.correction_started,
      correction_completed: summary.correction_completed,
      eligibility: %{
        approve: summary.approve_eligible,
        reject: summary.reject_eligible,
        start: summary.start_eligible,
        complete: summary.complete_eligible,
        fail: summary.fail_eligible
      },
      realm: Map.get(latest, :realm),
      data_source_id: Map.get(latest, :data_source_id),
      binding_id: Map.get(latest, :binding_id),
      source_from: source_boundary(events, :source_from, :min),
      source_to: source_boundary(events, :source_to, :max),
      updated_at: Map.get(latest, :occurred_at),
      affected_dashboards: affected_dashboards(events),
      comparison_reviews: comparison_reviews(events),
      failed_events: failed_events(events),
      audit_events: Enum.reverse(events)
    }
  end

  defp affected_dashboards(events) do
    events
    |> Enum.map(fn event ->
      context = nested_payload(event, "dashboard_context")

      case text(Map.get(context, "dashboard_id")) do
        nil ->
          nil

        dashboard_id ->
          %{
            dashboard_id: dashboard_id,
            dashboard_version: text(Map.get(context, "dashboard_version")),
            query:
              compact(%{
                "time_mode" => text(Map.get(context, "dashboard_time_mode")),
                "replay_run_id" => text(Map.get(context, "dashboard_replay_run_id")),
                "selected_data_view" => text(Map.get(context, "dashboard_data_view")),
                "limit_mode" => text(Map.get(context, "dashboard_limit_mode"))
              })
          }
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.dashboard_id)
  end

  defp comparison_reviews(events) do
    events
    |> Enum.map(fn event ->
      origin = nested_payload(event, "comparison_review_origin")

      case text(Map.get(origin, "request_event_id")) do
        nil -> nil
        request_event_id -> Map.put(origin, "request_event_id", request_event_id)
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&Map.get(&1, "request_event_id"))
  end

  defp failed_events(events) do
    events
    |> Enum.filter(&(Map.get(&1, :event_type) in [:backfill_failed, :import_failed]))
    |> Enum.map(fn event ->
      %{
        event_id: Map.get(event, :backfill_lifecycle_event_id),
        run_id: Map.get(event, :backfill_run_id),
        point_id: Map.get(event, :point_id),
        job_id: WorkflowEventEvidence.job_id(event),
        retryable?: WorkflowEventEvidence.retryable?(event),
        recovery_action: WorkflowEventEvidence.recovery_action(event),
        reason: Map.get(event, :reason)
      }
    end)
  end

  defp workflow(event) do
    case WorkflowEventEvidence.workflow(event) do
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) -> value
    end
  end

  defp nested_payload(%{payload: payload}, key) when is_map(payload) do
    case Map.get(payload, key) do
      value when is_map(value) -> value
      _value -> %{}
    end
  end

  defp nested_payload(_event, _key), do: %{}

  defp source_boundary(events, field, direction) do
    events
    |> Enum.map(&Map.get(&1, field))
    |> Enum.filter(&match?(%DateTime{}, &1))
    |> case do
      [] -> nil
      values when direction == :min -> Enum.min(values, DateTime)
      values -> Enum.max(values, DateTime)
    end
  end

  defp event_sort_key(event) do
    {occurred_at_sort_key(Map.get(event, :occurred_at)),
     Map.get(event, :backfill_lifecycle_event_id)}
  end

  defp occurred_at_sort_key(%DateTime{} = occurred_at),
    do: DateTime.to_unix(occurred_at, :microsecond)

  defp occurred_at_sort_key(_occurred_at), do: 0

  defp compact(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp text(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp text(value) when is_integer(value), do: Integer.to_string(value)
  defp text(_value), do: nil
end
