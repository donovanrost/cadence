defmodule Cadence.Reads.TelemetryLatest do
  @moduledoc """
  The latest value of a few points on many spacecraft at once (Compose B2's "Now" column, fe-ops):
  one current-value read of the mission, kept to the asked points × spacecraft. At most
  10 points and 500 spacecraft (5,000 values) per call; spacecraft must be the
  mission's. Values are the engineering value as JSON text (64-bit safe); a spacecraft with no
  value yet gets `value_json: nil`. `stale` follows the point's own stale timeout, else the
  fleet's (`FleetStatus.stale_after_s/0`).
  """

  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.{FleetStatus, Telemetry}
  alias Cadence.SpacecraftStore

  @max_points 10
  @max_spacecraft 500

  @spec load(binary(), binary(), term(), term(), DateTime.t()) ::
          {:ok, %{values: [map()]}} | {:error, {:invalid_params, map()}}
  def load(org, mission, point_ids, spacecraft_ids, now \\ DateTime.utc_now()) do
    with {:ok, points} <- ids(point_ids, :point_ids, @max_points),
         {:ok, crafts} <- ids(spacecraft_ids, :spacecraft_ids, @max_spacecraft),
         :ok <- mission_spacecraft(org, mission, crafts) do
      wanted_points = MapSet.new(points)
      wanted_crafts = MapSet.new(crafts)

      samples =
        org
        |> Telemetry.latest_values_for_mission(mission, [])
        |> Enum.filter(&(&1.point_id in wanted_points and &1.spacecraft_id in wanted_crafts))
        |> Map.new(&{{&1.spacecraft_id, &1.point_id}, &1})

      timeouts = stale_timeouts(org, mission, wanted_points)

      {:ok,
       %{
         values:
           for craft <- crafts,
               point <- points do
             value(craft, point, Map.get(samples, {craft, point}), Map.get(timeouts, point), now)
           end
       }}
    end
  end

  defp value(craft, point, nil, _timeout_s, _now),
    do: %{spacecraft_id: craft, point_id: point, value_json: nil, received_at: nil, stale: false}

  defp value(craft, point, sample, timeout_s, now) do
    received_at = sample.receipt_time || sample.generation_time

    %{
      spacecraft_id: craft,
      point_id: point,
      value_json: Jason.encode!(sample.engineering_value),
      received_at: received_at,
      stale: stale?(received_at, timeout_s || FleetStatus.stale_after_s(), now)
    }
  end

  defp stale?(%DateTime{} = at, timeout_s, now), do: DateTime.diff(now, at, :second) > timeout_s
  defp stale?(_at, _timeout_s, _now), do: false

  defp stale_timeouts(org, mission, wanted) do
    for point <- PointCatalog.list_points(org, mission),
        point.point_id in wanted,
        is_integer(point.stale_timeout_ms) and point.stale_timeout_ms > 0,
        into: %{},
        do: {point.point_id, div(point.stale_timeout_ms, 1000)}
  end

  defp mission_spacecraft(org, mission, crafts) do
    {:ok, found} = SpacecraftStore.fetch_spacecrafts(org, mission, crafts)

    case Enum.reject(crafts, &Map.has_key?(found, &1)) do
      [] ->
        :ok

      unknown ->
        invalid(%{spacecraft_ids: "aren't all this mission's spacecraft", unknown: unknown})
    end
  end

  defp ids(list, key, max) when is_list(list) do
    ids = Enum.uniq(list)

    cond do
      ids == [] ->
        invalid(%{key => "must list at least one id"})

      length(ids) > max ->
        invalid(%{key => "at most #{max}"})

      not Enum.all?(ids, &(is_binary(&1) and byte_size(&1) in 1..256)) ->
        invalid(%{key => "must be ids"})

      true ->
        {:ok, ids}
    end
  end

  defp ids(_list, key, _max), do: invalid(%{key => "must be a list of ids"})

  defp invalid(details), do: {:error, {:invalid_params, details}}
end
