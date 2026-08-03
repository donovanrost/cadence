defmodule Cadence.Reads.Alarms do
  @moduledoc """
  Mission-scoped read model for active and nominal limit conditions. The model
  is assembled from the canonical latest limit-state projection.
  """

  alias Cadence.Limits.Event
  alias Cadence.Reads.Limits, as: LimitReads

  @severity_order %{critical: 0, warning: 1, info: 2, nominal: 3}

  @spec snapshot(binary(), binary(), keyword()) :: map()
  def snapshot(organization_id, mission_id, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_list(opts) do
    observed_at = observed_at(opts)
    filters = Keyword.get(opts, :filters, %{})

    all_rows =
      organization_id
      |> latest_states(mission_id, opts)
      |> Enum.map(&row/1)

    rows =
      all_rows
      |> filter_rows(filters)
      |> Enum.sort_by(&sort_key/1)

    %{
      mission_id: mission_id,
      observed_at: observed_at,
      freshness: :current,
      rows: rows,
      spacecraft_ids:
        all_rows
        |> Enum.map(& &1.spacecraft_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort(),
      summary: summary_from_rows(mission_id, all_rows, observed_at)
    }
  end

  @spec summary(binary(), binary(), keyword()) :: map()
  def summary(organization_id, mission_id, opts \\ []) do
    snapshot(organization_id, mission_id, opts).summary
  end

  defp latest_states(organization_id, mission_id, opts) do
    case Keyword.get(opts, :latest_states) do
      callback when is_function(callback, 3) -> callback.(organization_id, mission_id, [])
      _missing -> LimitReads.latest_states_for_mission(organization_id, mission_id, [])
    end
  end

  defp observed_at(opts) do
    case Keyword.get(opts, :observed_at) do
      callback when is_function(callback, 0) -> callback.()
      _missing -> DateTime.utc_now()
    end
  end

  defp row(%Event{} = event) do
    %{
      id: event.limit_event_id,
      limit_event_id: event.limit_event_id,
      limit_definition_id: event.limit_definition_id,
      limit_definition_version: event.limit_definition_version,
      limit_set_name: event.limit_set_name,
      point_id: event.point_id,
      point_name: event.point_name,
      subsystem: subsystem(event.point_id),
      spacecraft_id: event.spacecraft_id,
      sample_id: event.sample_id,
      source_sample_type: event.source_sample_type,
      evaluated_value: event.evaluated_value,
      limit_state: event.limit_state,
      normalized_state: event.normalized_state,
      severity: severity(event.normalized_state),
      active?: event.violation,
      generation_time: event.generation_time,
      receipt_time: event.receipt_time
    }
  end

  defp filter_rows(rows, filters) do
    Enum.filter(rows, fn row ->
      severity_matches?(row, filter(filters, "severity", :severity)) and
        state_matches?(row, filter(filters, "state", :state)) and
        exact_matches?(row.spacecraft_id, filter(filters, "spacecraft_id", :spacecraft_id)) and
        query_matches?(row, filter(filters, "query", :query))
    end)
  end

  defp severity_matches?(_row, value) when value in [nil, "", "all"], do: true
  defp severity_matches?(row, severity), do: Atom.to_string(row.severity) == severity

  defp state_matches?(_row, value) when value in [nil, "", "all"], do: true
  defp state_matches?(row, "active"), do: row.active?
  defp state_matches?(row, "nominal"), do: not row.active?
  defp state_matches?(_row, _state), do: false

  defp exact_matches?(_actual, value) when value in [nil, "", "all"], do: true
  defp exact_matches?(actual, expected), do: actual == expected

  defp query_matches?(_row, value) when value in [nil, ""], do: true

  defp query_matches?(row, query) do
    query = String.downcase(query)

    Enum.any?([row.point_id, row.point_name, row.subsystem, row.limit_set_name], fn value ->
      is_binary(value) and String.contains?(String.downcase(value), query)
    end)
  end

  defp summary_from_rows(mission_id, rows, observed_at) do
    active_rows = Enum.filter(rows, & &1.active?)
    counts = Enum.frequencies_by(active_rows, & &1.severity)
    highest_severity = active_rows |> Enum.map(& &1.severity) |> highest_severity()

    %{
      mission_id: mission_id,
      observed_at: observed_at,
      latest_transition_at: latest_transition_at(rows),
      freshness: :current,
      active_count: length(active_rows),
      critical_count: Map.get(counts, :critical, 0),
      warning_count: Map.get(counts, :warning, 0),
      info_count: Map.get(counts, :info, 0),
      highest_severity: highest_severity,
      status: highest_severity || :nominal
    }
  end

  defp highest_severity([]), do: nil
  defp highest_severity(severities), do: Enum.min_by(severities, &Map.fetch!(@severity_order, &1))

  defp latest_transition_at([]), do: nil

  defp latest_transition_at(rows) do
    rows
    |> Enum.max_by(&DateTime.to_unix(&1.receipt_time, :microsecond))
    |> Map.fetch!(:receipt_time)
  end

  defp severity(:red), do: :critical
  defp severity(:yellow), do: :warning
  defp severity(:blue), do: :info
  defp severity(:green), do: :nominal

  defp subsystem(point_id) when is_binary(point_id) do
    point_id
    |> String.split([".", "/", ":"], parts: 2)
    |> List.first()
  end

  defp sort_key(row) do
    {Map.fetch!(@severity_order, row.severity), -DateTime.to_unix(row.receipt_time, :microsecond),
     row.spacecraft_id || "", row.point_id}
  end

  defp filter(filters, string_key, atom_key) when is_map(filters),
    do: Map.get(filters, string_key) || Map.get(filters, atom_key)
end
