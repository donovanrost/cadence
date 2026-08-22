defmodule Cadence.Dashboards.Sources.Telemetry.HistoricalWorkflows do
  @moduledoc false

  alias Cadence.Dashboards.{DataLinks, Frame}

  @active_event_types [
    :backfill_requested,
    :backfill_approved,
    :backfill_started,
    :backfill_failed,
    :backfill_retried,
    :import_requested,
    :import_approved,
    :import_started,
    :import_failed,
    :import_retried
  ]
  @terminal_event_types [
    :backfill_rejected,
    :backfill_completed,
    :import_rejected,
    :import_completed,
    :late_data_accepted,
    :late_data_rejected
  ]

  @spec annotate([Frame.t()], binary(), keyword(), keyword()) :: [Frame.t()]
  def annotate(frames, mission_id, query_opts, opts)
      when is_list(frames) and is_binary(mission_id) and is_list(query_opts) and is_list(opts) do
    events = lifecycle_events(mission_id, query_opts, opts)
    active_workflows = latest_active_workflows(events)
    terminal_outcomes = terminal_outcomes(events)

    if active_workflows == [] and terminal_outcomes == [] do
      frames
    else
      Enum.map(frames, fn frame ->
        frame
        |> put_active_workflows(active_workflows)
        |> put_terminal_outcomes(terminal_outcomes)
      end)
    end
  end

  defp lifecycle_events(mission_id, query_opts, opts) do
    case Keyword.fetch(opts, :backfill_lifecycle_events_fun) do
      {:ok, list_fun} when is_function(list_fun, 2) ->
        list_fun
        |> then(fn list_fun -> list_fun.(mission_id, query_opts) end)
        |> case do
          events when is_list(events) -> events
          {:ok, events} when is_list(events) -> events
          _other -> []
        end

      :error ->
        []
    end
  end

  defp latest_active_workflows(events) when is_list(events) do
    events
    |> Enum.group_by(&run_id/1)
    |> Enum.flat_map(fn
      {nil, run_events} -> Enum.filter(run_events, &active_event?/1)
      {_run_id, run_events} -> run_events |> latest_event() |> List.wrap()
    end)
    |> Enum.filter(&active_event?/1)
    |> Enum.map(&badge_context/1)
  end

  defp terminal_outcomes(events) when is_list(events) do
    events
    |> Enum.group_by(&run_id/1)
    |> Enum.flat_map(fn
      {nil, run_events} -> Enum.filter(run_events, &terminal_event?/1)
      {_run_id, run_events} -> run_events |> latest_event() |> List.wrap()
    end)
    |> Enum.filter(&terminal_event?/1)
    |> Enum.map(&badge_context/1)
  end

  defp latest_event(events) do
    events
    |> Enum.sort_by(&{occurred_at_us(&1), event_id(&1)}, :desc)
    |> List.first()
  end

  defp active_event?(event) do
    event_type(event) in @active_event_types and event_type(event) not in @terminal_event_types
  end

  defp terminal_event?(event), do: event_type(event) in @terminal_event_types

  defp put_active_workflows(%Frame{} = frame, workflows) do
    frame_workflows = matching_workflows(workflows, frame)

    case frame_workflows do
      [] ->
        frame

      [_workflow | _rest] ->
        evidence =
          frame_workflows
          |> Enum.map(&evidence_event/1)
          |> DataLinks.telemetry_backfill_lifecycle_event_evidence_refs()

        %Frame{
          frame
          | meta:
              frame.meta
              |> Map.put(:active_historical_workflows, frame_workflows)
              |> merge_evidence(evidence)
        }
    end
  end

  defp put_terminal_outcomes(%Frame{} = frame, outcomes) do
    frame_outcomes = matching_workflows(outcomes, frame)

    case frame_outcomes do
      [] ->
        frame

      [_outcome | _rest] ->
        evidence =
          frame_outcomes
          |> Enum.map(&evidence_event/1)
          |> DataLinks.telemetry_backfill_lifecycle_event_evidence_refs()

        %Frame{
          frame
          | meta:
              frame.meta
              |> Map.put(:historical_workflow_outcomes, frame_outcomes)
              |> merge_evidence(evidence)
        }
    end
  end

  defp matching_workflows(workflows, %Frame{} = frame) do
    workflows
    |> Enum.filter(&matches_frame?(&1, frame))
    |> Enum.uniq_by(&{Map.get(&1, :source_record_id), Map.get(&1, :run_id), Map.get(&1, :kind)})
  end

  defp matches_frame?(workflow, %Frame{} = frame) do
    workflow_point = Map.get(workflow, :point_id) || Map.get(workflow, :observable_id)
    frame_point = frame.meta[:point_id] || frame.meta[:observable_id]

    workflow_point in [nil, ""] or workflow_point == frame_point
  end

  defp badge_context(event) do
    %{
      category: :telemetry_backfill,
      kind: event_type(event),
      source_record_id: event_id(event),
      run_id: run_id(event),
      point_id: event_value(event, :point_id),
      observable_id: event_value(event, :observable_id),
      occurred_at: occurred_at(event)
    }
  end

  defp evidence_event(workflow) do
    %{
      backfill_lifecycle_event_id: Map.get(workflow, :source_record_id),
      occurred_at: Map.get(workflow, :occurred_at)
    }
  end

  defp merge_evidence(meta, []) when is_map(meta), do: meta

  defp merge_evidence(meta, evidence) when is_map(meta) and is_list(evidence) do
    Map.put(
      meta,
      :evidence,
      (List.wrap(Map.get(meta, :evidence)) ++ evidence)
      |> Enum.uniq_by(&evidence_identity/1)
    )
  end

  defp event_type(event), do: event_value(event, :event_type)
  defp run_id(event), do: event_value(event, :backfill_run_id)
  defp event_id(event), do: event_value(event, :backfill_lifecycle_event_id)
  defp occurred_at(event), do: event_value(event, :occurred_at)

  defp occurred_at_us(event) do
    case occurred_at(event) do
      %DateTime{} = occurred_at -> DateTime.to_unix(occurred_at, :microsecond)
      _missing -> 0
    end
  end

  defp event_value(event, key) when is_map(event) and is_atom(key) do
    Map.get(event, key, Map.get(event, Atom.to_string(key)))
  end

  defp event_value(_event, _key), do: nil

  defp evidence_identity(%{kind: kind, id: id}), do: {kind, id}
  defp evidence_identity(ref), do: ref
end
