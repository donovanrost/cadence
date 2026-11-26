defmodule Cadence.Reads.TelemetryLatest do
  @moduledoc """
  The latest value of a few points on many spacecraft at once (Compose B2's "Now" column, fe-ops):
  one current-value read restricted to the asked points × spacecraft (the store reads them in
  chunks of spacecraft), so the read holds only what the response holds. At most 10 points per
  call and no ceiling on spacecraft: a request is bounded by its RESPONSE, `@max_response_bytes`
  (8 MB, about 50,000 values), checked before the read from the request's shape and again on the
  encoded values. Spacecraft must be the mission's. Values are the engineering value as JSON text
  (64-bit safe); a spacecraft with no value yet gets `value_json: nil`. `stale` follows the
  point's own stale timeout, else the fleet's (`FleetStatus.stale_after_s/0`).
  """

  alias Cadence.Ops.PointCatalog
  alias Cadence.Reads.{FleetStatus, Telemetry}
  alias Cadence.SpacecraftStore

  @max_points 10
  @max_response_bytes 8_000_000
  # A value's JSON without its ids and value text: the keys, `received_at`, `stale`, punctuation.
  @value_overhead_bytes 110

  @spec load(binary(), binary(), term(), term(), DateTime.t()) ::
          {:ok, %{values: [map()]}} | {:error, {:invalid_params, map()}}
  def load(org, mission, point_ids, spacecraft_ids, now \\ DateTime.utc_now()) do
    with {:ok, points} <- ids(point_ids, :point_ids, @max_points),
         {:ok, crafts} <- ids(spacecraft_ids, :spacecraft_ids, nil),
         :ok <- within_response_bound(points, crafts),
         :ok <- mission_spacecraft(org, mission, crafts) do
      samples =
        org
        |> Telemetry.latest_values_for_mission(mission, point_ids: points, spacecraft_ids: crafts)
        |> Map.new(&{{&1.spacecraft_id, &1.point_id}, &1})

      timeouts = stale_timeouts(org, mission, MapSet.new(points))

      values =
        for craft <- crafts,
            point <- points do
          value(craft, point, Map.get(samples, {craft, point}), Map.get(timeouts, point), now)
        end

      with :ok <- encoded_within_bound(values), do: {:ok, %{values: values}}
    end
  end

  # Before the read: the smallest the response could be (each value's ids and fixed keys).
  defp within_response_bound(points, crafts) do
    floor =
      for craft <- crafts, point <- points, reduce: 0 do
        bytes -> bytes + @value_overhead_bytes + byte_size(craft) + byte_size(point)
      end

    if floor > @max_response_bytes, do: too_large(floor), else: :ok
  end

  # After: the values as they will be sent.
  defp encoded_within_bound(values) do
    bytes =
      Enum.reduce(values, 0, fn value, bytes ->
        bytes + @value_overhead_bytes + byte_size(value.spacecraft_id) +
          byte_size(value.point_id) + byte_size(value.value_json || "")
      end)

    if bytes > @max_response_bytes, do: too_large(bytes), else: :ok
  end

  defp too_large(bytes),
    do:
      invalid(%{
        spacecraft_ids:
          "the response would be about #{bytes} bytes; at most #{@max_response_bytes}",
        max_response_bytes: @max_response_bytes
      })

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
    {:ok, found} = SpacecraftStore.fetch_spacecrafts_in_batches(org, mission, crafts)

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

      is_integer(max) and length(ids) > max ->
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
