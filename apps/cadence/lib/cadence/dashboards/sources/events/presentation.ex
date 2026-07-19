defmodule Cadence.Dashboards.Sources.Events.Presentation do
  @moduledoc false

  import Cadence.Dashboards.Sources.Events.Reads,
    only: [source_capability_posture_value: 2]

  alias Cadence.Jobs

  def source_health_severity(%{source_health: :healthy}), do: :info
  def source_health_severity(%{source_health: :degraded}), do: :warning
  def source_health_severity(%{source_health: :unavailable}), do: :error
  def source_health_severity(%{source_health: :unknown}), do: :warning
  def source_health_severity(_event), do: :warning

  def source_health_title(event) do
    [
      event.logical_source |> stringify() |> String.replace("_", " "),
      "source",
      event.source_health |> stringify() |> String.replace("_", " ")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def source_watermark_severity(%{event_type: :retreated}), do: :warning
  def source_watermark_severity(%{event_type: :changed}), do: :info
  def source_watermark_severity(%{event_type: :advanced}), do: :info
  def source_watermark_severity(%{event_type: :observed}), do: :info
  def source_watermark_severity(_event), do: :warning

  def source_watermark_title(event) do
    [
      event.logical_source |> stringify() |> String.replace("_", " "),
      "watermark",
      event.event_type |> stringify() |> String.replace("_", " ")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def telemetry_backfill_lifecycle_severity(%{event_type: :backfill_failed}), do: :error
  def telemetry_backfill_lifecycle_severity(%{event_type: :import_failed}), do: :error
  def telemetry_backfill_lifecycle_severity(%{event_type: :backfill_rejected}), do: :warning
  def telemetry_backfill_lifecycle_severity(%{event_type: :import_rejected}), do: :warning
  def telemetry_backfill_lifecycle_severity(%{event_type: :late_data_rejected}), do: :warning
  def telemetry_backfill_lifecycle_severity(_event), do: :info

  def telemetry_backfill_lifecycle_title(event) do
    [
      event.observable_id || event.point_id,
      event.event_type |> stringify() |> String.replace("_", " ")
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def default_telemetry_backfill_workflow_job(event) do
    with run_id when is_binary(run_id) and run_id != "" <-
           telemetry_backfill_workflow_run_id(event),
         {:ok, %Jobs.Job{} = job} <-
           Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run_id) do
      job
    else
      _other -> nil
    end
  end

  def telemetry_backfill_workflow_run_id(event) do
    backfill_payload_value(event, :run_id) || event.backfill_run_id
  end

  def workflow_job_value(%Jobs.Job{} = job, key), do: Map.get(job, key)
  def workflow_job_value(_job, _key), do: nil

  def telemetry_revision_decision_severity(%{decision: :mark_conflict}), do: :warning
  def telemetry_revision_decision_severity(%{decision: :mark_superseded}), do: :warning
  def telemetry_revision_decision_severity(%{decision: :mark_advisory}), do: :info
  def telemetry_revision_decision_severity(%{decision: :mark_canonical}), do: :info
  def telemetry_revision_decision_severity(_event), do: :info

  def telemetry_revision_decision_title(event) do
    [
      event.observable_id || event.point_id,
      "revision",
      telemetry_revision_decision_label(event.decision)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def telemetry_revision_decision_label(nil), do: nil

  def telemetry_revision_decision_label(decision) do
    decision
    |> stringify()
    |> String.replace("mark_", "")
    |> String.replace("_", " ")
  end

  def source_capability_posture_title(event) do
    [
      source_capability_posture_label(source_capability_posture_value(event, :logical_source)),
      "capability",
      source_capability_posture_label(source_capability_posture_value(event, :status))
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def source_capability_posture_text(event, key) do
    case source_capability_posture_value(event, key) do
      nil -> nil
      [] -> nil
      values when is_list(values) -> Enum.map_join(values, ", ", &stringify/1)
      value -> stringify(value)
    end
  end

  def source_capability_posture_label(nil), do: nil

  def source_capability_posture_label(value) do
    value
    |> stringify()
    |> String.replace("_", " ")
  end

  def backfill_payload_value(%{payload: payload}, key) when is_map(payload) and is_atom(key) do
    Map.get(payload, key, Map.get(payload, Atom.to_string(key)))
  end

  def backfill_payload_value(_event, _key), do: nil

  def state_value(state, key) when is_map(state), do: get_attr(state, key)
  def state_value(_state, _key), do: nil

  def repeat(value, values), do: Enum.map(values, fn _value -> value end)

  def fallback(nil, value), do: value
  def fallback(value, _fallback), do: value

  def normalize_datetime(%DateTime{} = datetime), do: datetime

  def normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  def normalize_datetime(_value), do: nil

  def normalize_string_list(nil), do: []
  def normalize_string_list(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  def normalize_string_list(value) when is_binary(value), do: [value]
  def normalize_string_list(_value), do: []

  def compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> value in [nil, "", []] end)
    |> Map.new()
  end

  defp get_attr(nil, _key), do: nil

  defp get_attr(%_struct{} = struct, key) when is_atom(key) do
    struct
    |> Map.from_struct()
    |> get_attr(key)
  end

  defp get_attr(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp get_attr(_value, _key), do: nil

  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: inspect(value)
end
