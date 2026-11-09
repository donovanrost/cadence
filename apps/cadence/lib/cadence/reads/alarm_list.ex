defmodule Cadence.Reads.AlarmList do
  @moduledoc """
  Limit alarms for a mission, enriched for operators: the point's `unit` and `description`, the thresholds of the
  limit definition that produced each state, and when the point first entered
  its current state (`first_crossed_at`).

  Built on `Cadence.Reads.Alarms` (the latest limit-state projection).
  Severity uses the console vocabulary: `critical | caution | nominal`.
  """

  alias Cadence.Limits.Event
  alias Cadence.Reads.Alarms
  alias Cadence.Reads.Limits, as: LimitReads
  alias Cadence.Reads.PointInfo

  @history_depth 200
  @enrich_limit 200

  @doc """
  Options: `:spacecraft_id`, `:state` (`"active" | "nominal" | "all"`, default
  `"active"`), `:severity` (`"critical" | "caution"`), `:query`.
  """
  @spec load(binary(), binary(), map()) :: map()
  def load(organization_id, mission_id, filters) do
    snapshot =
      Alarms.snapshot(organization_id, mission_id,
        filters: %{
          "spacecraft_id" => filters[:spacecraft_id],
          "state" => filters[:state] || "active",
          "severity" => alarms_severity(filters[:severity]),
          "query" => filters[:query]
        }
      )

    rows = snapshot.rows
    thresholds = thresholds(organization_id, mission_id, Enum.take(rows, @enrich_limit))
    points = if rows == [], do: %{}, else: PointInfo.by_id(organization_id, mission_id)

    %{
      observed_at: snapshot.observed_at,
      summary: summary(snapshot.summary),
      alarms:
        rows
        |> Enum.with_index()
        |> Enum.map(fn {row, index} ->
          enriched? = index < @enrich_limit

          row
          |> Map.merge(Map.get(points, row.point_id, PointInfo.unknown()))
          |> Map.put(:severity, severity(row.normalized_state))
          |> Map.put(:thresholds, Map.get(thresholds, definition_key(row)))
          |> Map.put(
            :first_crossed_at,
            if(enriched?, do: first_crossed_at(organization_id, mission_id, row))
          )
        end)
    }
  end

  @doc false
  @spec first_crossed_from_history(atom(), [Event.t()]) :: DateTime.t() | nil
  def first_crossed_from_history(current_state, newest_first) do
    newest_first
    |> Enum.take_while(&(&1.normalized_state == current_state))
    |> List.last()
    |> case do
      nil -> nil
      %Event{} = event -> event.generation_time || event.receipt_time
    end
  end

  defp first_crossed_at(organization_id, mission_id, row) do
    history =
      LimitReads.event_history(organization_id, mission_id, row.point_id,
        spacecraft_id: row.spacecraft_id,
        limit: @history_depth,
        order: :desc
      )

    first_crossed_from_history(row.normalized_state, history)
  end

  defp thresholds(organization_id, mission_id, rows) do
    rows
    |> Enum.map(&definition_key/1)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn
      {id, version} = key, acc when is_binary(id) and is_integer(version) ->
        case Cadence.Limits.fetch_limit_definition(organization_id, mission_id, id, version) do
          {:ok, definition} -> Map.put(acc, key, definition.thresholds)
          {:error, _reason} -> acc
        end

      _key, acc ->
        acc
    end)
  end

  defp definition_key(row), do: {row.limit_definition_id, row.limit_definition_version}

  defp summary(summary) do
    %{
      active: summary.active_count,
      critical: summary.critical_count,
      caution: summary.warning_count,
      latest_transition_at: summary.latest_transition_at
    }
  end

  defp severity(:red), do: :critical
  defp severity(:yellow), do: :caution
  defp severity(_other), do: :nominal

  defp alarms_severity("critical"), do: "critical"
  defp alarms_severity("caution"), do: "warning"
  defp alarms_severity(_other), do: nil
end
