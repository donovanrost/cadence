defmodule Cadence.Telemetry.Storage.BackfillLifecycleGroup do
  @moduledoc """
  Shared lifecycle rules for grouped historical telemetry workflow requests.

  Dashboard actions and inspectors both need to answer which request-group items
  are still effective after correction workflows. This module keeps those rules
  out of presentation code.
  """

  alias Cadence.Telemetry.Storage.BackfillLifecycleEvent

  @type action_eligibility :: %{
          request: non_neg_integer(),
          approve: non_neg_integer(),
          reject: non_neg_integer(),
          start: non_neg_integer(),
          complete: non_neg_integer(),
          fail: non_neg_integer()
        }

  @type summary :: %{
          state: binary(),
          terminal?: boolean(),
          size: non_neg_integer(),
          progress: binary(),
          requested: non_neg_integer(),
          approved: non_neg_integer(),
          started: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer(),
          resolved_failed: non_neg_integer(),
          retry_resolved: non_neg_integer(),
          correction_requested: non_neg_integer(),
          correction_started: non_neg_integer(),
          correction_completed: non_neg_integer(),
          correction_superseded: non_neg_integer(),
          request_eligible: non_neg_integer(),
          approve_eligible: non_neg_integer(),
          reject_eligible: non_neg_integer(),
          start_eligible: non_neg_integer(),
          complete_eligible: non_neg_integer(),
          fail_eligible: non_neg_integer(),
          retryable_failed: non_neg_integer(),
          nonretryable_failed: non_neg_integer(),
          failed_items: binary() | nil,
          failed_item_events: binary() | nil
        }

  @type transition_error :: {:no_eligible_items, term()}

  @spec summary([BackfillLifecycleEvent.t()], [BackfillLifecycleEvent.t()], keyword()) ::
          summary()
  def summary(events, lifecycle_events, opts \\ [])
      when is_list(events) and is_list(lifecycle_events) and is_list(opts) do
    retry_ready_fun = Keyword.get(opts, :retry_ready_fun, fn _event -> false end)
    item_count = item_count(events)
    failed_events = stage_events(events, "failed")
    resolution_event_ids = resolution_event_ids(lifecycle_events)
    correction_run_ids = correction_run_ids(lifecycle_events)
    effective_events = effective_events(events, correction_run_ids)
    eligibility = action_eligibility(events)

    correction_events =
      Enum.filter(events, &MapSet.member?(correction_run_ids, &1.backfill_run_id))

    requested = stage_count(effective_events, "requested")
    approved = stage_count(effective_events, "approved")
    started = stage_count(effective_events, "started")
    completed = stage_count(effective_events, "completed")

    resolved_failed_events = resolved_failed_events(failed_events, resolution_event_ids.all)

    retry_resolved_failed_events =
      resolved_failed_events(failed_events, resolution_event_ids.retry)

    correction_requested_failed_events =
      resolved_failed_events(failed_events, resolution_event_ids.correction)

    correction_superseded_failed_events =
      resolved_failed_events(failed_events, resolution_event_ids.correction_completed)

    active_failed_events = failed_events -- resolved_failed_events
    failed = stage_item_count(active_failed_events)
    resolved_failed = stage_item_count(resolved_failed_events)
    retry_resolved = stage_item_count(retry_resolved_failed_events)
    correction_requested = stage_item_count(correction_requested_failed_events)
    correction_superseded = stage_item_count(correction_superseded_failed_events)
    correction_started = stage_count(correction_events, "started")
    correction_completed = stage_count(correction_events, "completed")

    retryable_failed_events =
      Enum.filter(active_failed_events, fn event ->
        retryable?(event) and retry_ready_fun.(event)
      end)

    nonretryable_failed_events = Enum.reject(active_failed_events, &retryable?/1)

    state = state(item_count, requested, approved, started, completed, failed)

    %{
      state: state,
      terminal?: terminal?(state),
      size: item_count,
      progress: progress(completed, item_count, failed, resolved_failed),
      requested: requested,
      approved: approved,
      started: started,
      completed: completed,
      failed: failed,
      resolved_failed: resolved_failed,
      retry_resolved: retry_resolved,
      correction_requested: correction_requested,
      correction_started: correction_started,
      correction_completed: correction_completed,
      correction_superseded: correction_superseded,
      request_eligible: eligibility.request,
      approve_eligible: eligibility.approve,
      reject_eligible: eligibility.reject,
      start_eligible: eligibility.start,
      complete_eligible: eligibility.complete,
      fail_eligible: eligibility.fail,
      retryable_failed: stage_item_count(retryable_failed_events),
      nonretryable_failed: stage_item_count(nonretryable_failed_events),
      failed_items: failed_items(active_failed_events),
      failed_item_events: failed_item_events(active_failed_events)
    }
  end

  @spec transition_candidates([BackfillLifecycleEvent.t()], term()) ::
          {:ok, [BackfillLifecycleEvent.t()]} | {:error, transition_error()}
  def transition_candidates(events, stage) when is_list(events) do
    case stage_candidates(events, stage) do
      [_event | _events] = candidates -> {:ok, candidates}
      [] -> {:error, {:no_eligible_items, stage}}
    end
  end

  @spec transition_sources([BackfillLifecycleEvent.t()], term()) ::
          {:ok, [BackfillLifecycleEvent.t()]} | {:error, transition_error()}
  def transition_sources(events, stage) when is_list(events) do
    case stage_sources(events, stage) do
      [_event | _events] = sources -> {:ok, sources}
      [] -> {:error, {:no_eligible_items, stage}}
    end
  end

  @spec stage_candidates([BackfillLifecycleEvent.t()], term()) :: [BackfillLifecycleEvent.t()]
  def stage_candidates(events, stage) when is_list(events) do
    requested_events = effective_requested_events(events)
    effective_events = effective_events_for_requested(events, requested_events)
    latest_stage_by_item = latest_stage_by_item(effective_events)

    requested_events
    |> Enum.filter(fn requested_event ->
      item_key = item_key(requested_event)
      latest_stage = Map.get(latest_stage_by_item, item_key)
      stage_eligible?(stage, latest_stage)
    end)
    |> Enum.sort_by(&event_sort_key/1)
  end

  @spec stage_sources([BackfillLifecycleEvent.t()], term()) :: [BackfillLifecycleEvent.t()]
  def stage_sources(events, stage) when is_list(events) do
    requested_events = effective_requested_events(events)
    effective_events = effective_events_for_requested(events, requested_events)
    latest_stage_by_item = latest_stage_by_item(effective_events)
    latest_event_by_item = latest_event_by_item(effective_events)

    requested_events
    |> Enum.filter(fn requested_event ->
      item_key = item_key(requested_event)
      latest_stage = Map.get(latest_stage_by_item, item_key)
      stage_eligible?(stage, latest_stage)
    end)
    |> Enum.map(fn requested_event ->
      Map.fetch!(latest_event_by_item, item_key(requested_event))
    end)
    |> Enum.sort_by(&event_sort_key/1)
  end

  @spec action_eligibility([BackfillLifecycleEvent.t()]) :: action_eligibility()
  def action_eligibility(events) when is_list(events) do
    requested_events = effective_requested_events(events)
    effective_events = effective_events_for_requested(events, requested_events)
    latest_stage_by_item = latest_stage_by_item(effective_events)

    [
      request: "requested",
      approve: "approved",
      reject: "rejected",
      start: "started",
      complete: "completed",
      fail: "failed"
    ]
    |> Map.new(fn {action, stage} ->
      {action, stage_eligible_count(requested_events, latest_stage_by_item, stage)}
    end)
  end

  @spec effective_requested_events([BackfillLifecycleEvent.t()]) :: [BackfillLifecycleEvent.t()]
  def effective_requested_events(events) when is_list(events) do
    requested_events = Enum.filter(events, &requested_event?/1)

    latest_correction_requests_by_item =
      requested_events
      |> Enum.filter(&correction_request_event?/1)
      |> Map.new(fn event -> {item_key(event), event} end)

    latest_correction_event_ids =
      latest_correction_requests_by_item
      |> Map.values()
      |> Enum.map(& &1.backfill_lifecycle_event_id)
      |> MapSet.new()

    correction_item_keys =
      latest_correction_requests_by_item
      |> Map.keys()
      |> MapSet.new()

    Enum.filter(requested_events, fn event ->
      key = item_key(event)

      MapSet.member?(latest_correction_event_ids, event.backfill_lifecycle_event_id) or
        not MapSet.member?(correction_item_keys, key)
    end)
  end

  @spec effective_events([BackfillLifecycleEvent.t()]) :: [BackfillLifecycleEvent.t()]
  def effective_events(events) when is_list(events) do
    effective_events_for_requested(events, effective_requested_events(events))
  end

  @spec effective_events([BackfillLifecycleEvent.t()], MapSet.t()) :: [BackfillLifecycleEvent.t()]
  def effective_events(events, %MapSet{} = correction_run_ids) when is_list(events) do
    correction_item_keys =
      events
      |> Enum.filter(&MapSet.member?(correction_run_ids, &1.backfill_run_id))
      |> Enum.map(&item_key/1)
      |> MapSet.new()

    Enum.filter(events, fn event ->
      key = item_key(event)

      not MapSet.member?(correction_item_keys, key) or
        MapSet.member?(correction_run_ids, event.backfill_run_id)
    end)
  end

  @spec correction_run_ids([BackfillLifecycleEvent.t()]) :: MapSet.t()
  def correction_run_ids(events) when is_list(events) do
    events
    |> Enum.filter(&correction_request_event?/1)
    |> Enum.map(& &1.backfill_run_id)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  @spec latest_stage_by_item([BackfillLifecycleEvent.t()]) :: map()
  def latest_stage_by_item(events) when is_list(events) do
    Enum.reduce(events, %{}, fn event, stages ->
      case payload_value(event, :stage) do
        stage when is_binary(stage) and stage != "" ->
          Map.put(stages, item_key(event), stage)

        _stage ->
          stages
      end
    end)
  end

  @spec latest_event_by_item([BackfillLifecycleEvent.t()]) :: map()
  def latest_event_by_item(events) when is_list(events) do
    Enum.reduce(events, %{}, fn event, latest_events ->
      case payload_value(event, :stage) do
        stage when is_binary(stage) and stage != "" ->
          Map.put(latest_events, item_key(event), event)

        _stage ->
          latest_events
      end
    end)
  end

  @spec stage_events([BackfillLifecycleEvent.t()], binary()) :: [BackfillLifecycleEvent.t()]
  def stage_events(events, stage) when is_list(events) do
    Enum.filter(events, &(payload_value(&1, :stage) == stage))
  end

  @spec stage_eligible?(binary(), binary() | nil) :: boolean()
  def stage_eligible?("requested", nil), do: true
  def stage_eligible?("requested", _stage), do: false
  def stage_eligible?("approved", "requested"), do: true
  def stage_eligible?("rejected", stage), do: stage in ["requested", "approved"]
  def stage_eligible?("started", stage), do: stage in ["approved", "retried"]

  def stage_eligible?("completed", stage), do: stage in ["started", "retried"]

  def stage_eligible?("failed", stage), do: stage in ["started", "retried"]

  def stage_eligible?(_target_stage, _current_stage), do: false

  @spec item_key(BackfillLifecycleEvent.t()) :: term()
  def item_key(event) do
    payload_value(event, :request_item_index) || event.backfill_run_id
  end

  @spec payload_value(BackfillLifecycleEvent.t() | map() | nil, atom()) :: term()
  def payload_value(%{payload: payload}, key), do: payload_value(payload, key)

  def payload_value(payload, key) when is_map(payload) do
    Map.get(payload, Atom.to_string(key), Map.get(payload, key))
  end

  def payload_value(_payload, _key), do: nil

  defp effective_events_for_requested(events, requested_events) do
    correction_run_ids = correction_run_ids(requested_events)

    correction_item_keys =
      requested_events
      |> Enum.filter(&correction_request_event?/1)
      |> Enum.map(&item_key/1)
      |> MapSet.new()

    Enum.filter(events, fn event ->
      key = item_key(event)

      not MapSet.member?(correction_item_keys, key) or
        MapSet.member?(correction_run_ids, event.backfill_run_id)
    end)
  end

  defp stage_eligible_count(requested_events, latest_stage_by_item, stage) do
    Enum.count(requested_events, fn event ->
      latest_stage = Map.get(latest_stage_by_item, item_key(event))
      stage_eligible?(stage, latest_stage)
    end)
  end

  defp resolution_event_ids(lifecycle_events) do
    retry =
      lifecycle_events
      |> Enum.map(&payload_value(&1, :retry_source_event_id))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    correction =
      lifecycle_events
      |> Enum.map(&payload_value(&1, :corrects_event_id))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    correction_completed =
      lifecycle_events
      |> Enum.filter(&(payload_value(&1, :stage) == "completed"))
      |> Enum.map(&payload_value(&1, :corrects_event_id))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    %{
      retry: retry,
      correction: correction,
      correction_completed: correction_completed,
      all: MapSet.union(retry, correction)
    }
  end

  defp resolved_failed_events(failed_events, resolved_event_ids) do
    Enum.filter(
      failed_events,
      &MapSet.member?(resolved_event_ids, &1.backfill_lifecycle_event_id)
    )
  end

  defp item_count(events) do
    events
    |> Enum.flat_map(fn event ->
      [
        payload_value(event, :request_item_count),
        event.backfill_run_id
      ]
    end)
    |> Enum.reduce(0, &item_count_reducer/2)
  end

  defp item_count_reducer(count, max) when is_integer(count), do: max(count, max)
  defp item_count_reducer(run_id, max) when is_binary(run_id), do: max(1, max)
  defp item_count_reducer(_value, max), do: max

  defp stage_count(events, stage) do
    events
    |> stage_events(stage)
    |> stage_item_count()
  end

  defp stage_item_count(events) do
    events
    |> Enum.map(&item_key/1)
    |> Enum.uniq()
    |> length()
  end

  defp state(size, _requested, _approved, _started, completed, failed)
       when size > 0 and completed == size and failed == 0 do
    "completed"
  end

  defp state(size, _requested, _approved, _started, _completed, failed)
       when size > 0 and failed == size do
    "failed"
  end

  defp state(size, _requested, _approved, _started, completed, failed)
       when size > 0 and completed + failed >= size and failed > 0 do
    "completed_with_failures"
  end

  defp state(_size, _requested, _approved, _started, _completed, failed)
       when failed > 0 do
    "failing"
  end

  defp state(_size, _requested, _approved, started, _completed, _failed)
       when started > 0 do
    "running"
  end

  defp state(size, _requested, approved, _started, _completed, _failed)
       when size > 0 and approved == size do
    "approved"
  end

  defp state(_size, _requested, approved, _started, _completed, _failed)
       when approved > 0 do
    "partially_approved"
  end

  defp state(_size, requested, _approved, _started, _completed, _failed)
       when requested > 0 do
    "requested"
  end

  defp state(_size, _requested, _approved, _started, _completed, _failed), do: "unknown"

  defp terminal?(state) when state in ["completed", "failed", "completed_with_failures"],
    do: true

  defp terminal?(_state), do: false

  defp progress(completed, item_count, failed, 0) do
    "#{completed}/#{item_count} completed, #{failed} failed"
  end

  defp progress(completed, item_count, failed, resolved_failed) do
    "#{completed}/#{item_count} completed, #{failed} failed, #{resolved_failed} resolved"
  end

  defp failed_items([]), do: nil

  defp failed_items(events) do
    events
    |> Enum.map(&(&1.point_id || &1.observable_id || &1.backfill_run_id))
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp failed_item_events([]), do: nil

  defp failed_item_events(events) do
    events
    |> Enum.sort_by(&event_sort_key/1)
    |> Enum.map_join("; ", fn event ->
      [
        failed_item_event_token("label", failed_item_label(event)),
        failed_item_event_token("run", event.backfill_run_id),
        failed_item_event_token("event", event.backfill_lifecycle_event_id),
        failed_item_event_token("recovery", failed_item_recovery_action(event)),
        failed_item_event_token("retryable", retryable?(event))
      ]
      |> Enum.join(" ")
    end)
  end

  defp failed_item_event_token(key, value), do: "#{key}=#{URI.encode(to_string(value))}"

  defp failed_item_label(event),
    do: event.point_id || event.observable_id || event.backfill_run_id || "unknown"

  defp failed_item_recovery_action(event) do
    recovery_action =
      event
      |> payload_value(:source)
      |> payload_value(:failure)
      |> payload_value(:recovery_action)

    if is_binary(recovery_action) and recovery_action != "", do: recovery_action, else: "unknown"
  end

  defp retryable?(event) do
    failure =
      event
      |> payload_value(:source)
      |> payload_value(:failure)

    case payload_value(failure, :recovery_action) do
      "correct_workflow_request" ->
        false

      _recovery_action ->
        case payload_value(failure, :retryable) do
          false -> false
          "false" -> false
          _other -> true
        end
    end
  end

  defp requested_event?(event), do: payload_value(event, :stage) == "requested"

  defp correction_request_event?(event) do
    case payload_value(event, :corrects_event_id) do
      value when is_binary(value) -> value != ""
      _value -> false
    end
  end

  defp event_sort_key(event) do
    {payload_value(event, :request_item_index) || 0, event.backfill_run_id}
  end
end
