defmodule Cadence.Reads.PassGeometry do
  @moduledoc """
  Predicted geometry on contacts and opportunities (#892, slice 4 of #732). Each page is matched
  to predicted passes in one query (`Cadence.GroundNetworks.PredictedPasses.match/3`): same
  spacecraft and station, overlapping windows, the longest overlap winning.

  Contacts (the passes read, booked and hand-started rows):

    * `max_elevation_deg`: the provider's value when the booking reports one, else the matched
      predicted pass's, else `nil`;
    * `elevation_source`: `"provider"`, `"predicted"` or `nil`, `nil` exactly when the elevation
      is;
    * `predicted_pass_id`: the matched predicted pass, or `nil`.

  Opportunities (Book a pass offers, a plan's alternatives) carry the same three plus:

    * `tca`: the matched predicted pass's TCA, or `nil`;
    * `no_predicted_pass`: `true` when prediction covers the window (`predictable/3`) and no
      predicted pass matches it, the provider offering a window no geometry backs (a stale
      element set, a wrong station location, a provider error). `false` when one matches. `nil`
      when prediction can't say (no element set, deep space, no station location, beyond the
      horizon). The opportunity is shown either way, never dropped.

  A booking's provider-reported window and `next_pass`/`next_aos_at` are untouched: a predicted
  pass is geometry, not a booking.
  """

  alias Cadence.GroundNetworks.PredictedPasses

  @doc "Annotates contact rows (the passes read) with their predicted geometry."
  @spec contacts(binary(), binary(), [map()], DateTime.t()) :: [map()]
  def contacts(organization_id, mission_id, rows, now \\ DateTime.utc_now())

  def contacts(_organization_id, _mission_id, [], _now), do: []

  def contacts(organization_id, mission_id, rows, now) do
    indexed = Enum.with_index(rows)
    windows = Enum.map(indexed, fn {row, i} -> window(i, row.spacecraft_id, row, now) end)
    matches = PredictedPasses.match(organization_id, mission_id, windows)

    Enum.map(indexed, fn {row, i} -> put_geometry(row, Map.get(matches, i)) end)
  end

  @doc """
  Annotates one spacecraft's opportunities (offers or plan alternatives, each with `station`,
  `starts_at`, `ends_at` and an optional provider `max_elevation_deg`), flagging those no
  predicted pass backs.
  """
  @spec opportunities(binary(), binary(), binary(), [map()]) :: [map()]
  def opportunities(_organization_id, _mission_id, _spacecraft_id, []), do: []

  def opportunities(organization_id, mission_id, spacecraft_id, opportunities) do
    indexed = Enum.with_index(opportunities)
    windows = Enum.map(indexed, fn {o, i} -> window(i, spacecraft_id, o, nil) end)
    matches = PredictedPasses.match(organization_id, mission_id, windows)
    covered = PredictedPasses.predictable(organization_id, mission_id, windows)

    Enum.map(indexed, fn {opportunity, i} ->
      match = Map.get(matches, i)

      opportunity
      |> put_geometry(match)
      |> Map.put(:tca, match && match.tca)
      |> Map.put(:no_predicted_pass, flag(match, MapSet.member?(covered, i)))
    end)
  end

  defp flag(%{} = _match, _covered), do: false
  defp flag(nil, true), do: true
  defp flag(nil, false), do: nil

  defp put_geometry(row, match) do
    provider = provider_elevation(row)

    {elevation, source} =
      cond do
        provider != nil -> {provider, "provider"}
        match != nil -> {match.max_elevation_deg, "predicted"}
        true -> {nil, nil}
      end

    Map.merge(row, %{
      max_elevation_deg: elevation,
      elevation_source: source,
      predicted_pass_id: match && match.predicted_pass_id
    })
  end

  # Only a number the provider reported counts; a predicted value from an earlier annotation is
  # never taken for the provider's.
  defp provider_elevation(%{elevation_source: "predicted"}), do: nil

  defp provider_elevation(row) do
    case Map.get(row, :max_elevation_deg) do
      value when is_number(value) -> value
      _none -> nil
    end
  end

  # A live hand-started contact has no end yet: it is matched up to now.
  defp window(key, spacecraft_id, row, now) do
    starts_at = Map.get(row, :starts_at)

    %{
      key: key,
      spacecraft_id: spacecraft_id,
      ground_station_id: station_id(row),
      starts_at: starts_at,
      ends_at: Map.get(row, :ends_at) || open_end(starts_at, now)
    }
  end

  defp open_end(%DateTime{} = starts_at, %DateTime{} = now),
    do: if(DateTime.after?(now, starts_at), do: now, else: DateTime.add(starts_at, 1))

  defp open_end(_starts_at, _now), do: nil

  defp station_id(%{station: %{id: id}}) when is_binary(id), do: id
  defp station_id(_row), do: nil
end
