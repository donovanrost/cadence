defmodule CadenceWeb.Console.PointJSON do
  @moduledoc "Wire shapes for point history and limit intervals. Contract: docs/apogee/api/ops.md."

  alias Cadence.Limits.DefinitionInterval
  alias CadenceWeb.Console.WireValue

  @thresholds [
    {"red_low", :red_low},
    {"yellow_low", :yellow_low},
    {"yellow_high", :yellow_high},
    {"red_high", :red_high}
  ]

  @spec history(binary(), map(), map(), map()) :: map()
  def history(point_id, window, history, info) do
    %{
      point_id: point_id,
      unit: info.unit,
      description: info.description,
      spacecraft_id: window.spacecraft_id,
      from: window.from,
      to: window.to,
      bucket_width_ms: history.bucket_width_ms,
      truncated: history.truncated,
      buckets:
        Enum.map(history.buckets, fn bucket ->
          %{
            t: bucket.t,
            t_end: bucket.t_end,
            min: WireValue.encode(bucket.min),
            max: WireValue.encode(bucket.max),
            mean: WireValue.encode(bucket.mean),
            count: bucket.count
          }
        end)
    }
  end

  @spec limit_intervals(binary(), map(), [DefinitionInterval.t()]) :: map()
  def limit_intervals(point_id, window, intervals) do
    %{
      point_id: point_id,
      spacecraft_id: window.spacecraft_id,
      from: window.from,
      to: window.to,
      intervals: Enum.map(intervals, &interval/1)
    }
  end

  defp interval(%DefinitionInterval{} = interval) do
    thresholds = interval.thresholds || %{}

    %{
      from: interval.active_from,
      to: interval.active_to,
      limit_set_name: interval.limit_set_name,
      limit_definition_id: interval.limit_definition_id,
      limit_definition_version: interval.limit_definition_version,
      scope: %{
        type: interval.scope_type && to_string(interval.scope_type),
        ref: interval.scope_ref
      },
      thresholds:
        Map.new(@thresholds, fn {key, atom} ->
          {key, WireValue.encode(Map.get(thresholds, key, Map.get(thresholds, atom)))}
        end)
    }
  end
end
