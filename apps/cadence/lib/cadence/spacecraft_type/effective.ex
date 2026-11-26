defmodule Cadence.SpacecraftType.Effective do
  @moduledoc """
  A spacecraft's effective configuration: its pinned profile version with its overrides
  applied. Pure. Used by route materialization, previews and reads.
  """

  alias Cadence.SpacecraftType

  @doc """
  `overrides` is `%{path => %{value: term}}` (`Cadence.SpacecraftStore.Overrides.list/3`).
  Returns the profile's configurable values and its routing rules, with routing overrides
  applied (excluded stations removed, opted-out rules disabled).
  """
  @spec resolve(SpacecraftType.t(), map()) :: map()
  def resolve(%SpacecraftType{} = profile, overrides) do
    base = %{
      "downlink_protocol" => Atom.to_string(profile.downlink_protocol),
      "uplink_protocol" => Atom.to_string(profile.uplink_protocol),
      "packet_protocol" => Atom.to_string(profile.packet_protocol),
      "frame_parameters" => profile.frame_parameters || %{},
      "catalog_revision_id" => profile.catalog_revision_id,
      "composition_id" => profile.composition_id,
      "handled_apids" => profile.handled_apids
    }

    values =
      Enum.reduce(overrides, base, fn
        {"routing." <> _rest, _override}, acc ->
          acc

        {"frame_parameters." <> key, %{value: value}}, acc ->
          put_in(acc, ["frame_parameters", key], value)

        {path, %{value: value}}, acc ->
          Map.put(acc, path, value)
      end)

    Map.put(
      values,
      "routing_rules",
      Enum.map(profile.routing_rules, &apply_routing(&1, overrides))
    )
  end

  defp apply_routing(rule, overrides) do
    id = rule["id"]
    excluded = get_value(overrides, "routing.#{id}.excluded_stations", [])

    rule
    |> Map.update!("stations", fn stations ->
      Enum.reject(stations, &(&1["ground_station_id"] in excluded))
    end)
    |> Map.put("enabled", rule["enabled"] and get_value(overrides, "routing.#{id}.enabled", true))
  end

  defp get_value(overrides, path, default) do
    case Map.get(overrides, path) do
      %{value: value} when not is_nil(value) -> value
      _ -> default
    end
  end
end
