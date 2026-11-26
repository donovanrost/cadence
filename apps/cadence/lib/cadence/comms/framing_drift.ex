defmodule Cadence.Comms.FramingDrift do
  @moduledoc """
  Read-only audit (DECISIONS #33): where a spacecraft's effective profile framing differs from
  the `ingress_metadata` of a transport that feeds it (an active inbound route). Today decode
  uses the transport values, so every difference is something a profile-authoritative
  generation would change.

  Result: one item per `{profile, transport}` with the spacecraft count and the differing
  fields.
  """

  alias Cadence.Comms.{RoutingRuleStore, TransportStore}
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Overrides
  alias Cadence.SpacecraftType.Effective
  alias Cadence.SpacecraftTypeStore

  @fields [
    {"frame_size", nil},
    {"secondary_header_length", 0},
    {"ocf_length", 4},
    {"fecf", false}
  ]

  @type item :: %{
          profile: %{id: String.t(), name: String.t()},
          transport: %{id: String.t(), name: String.t()},
          spacecraft_count: pos_integer(),
          differences: [%{path: String.t(), profile_value: term(), transport_value: term()}]
        }

  @spec audit(String.t(), String.t(), [String.t()] | :all) :: [item()]
  def audit(organization_id, mission_id, only \\ :all) do
    transports =
      organization_id
      |> TransportStore.list_transports(mission_id)
      |> Map.new(&{&1.transport_id, &1})

    spacecraft =
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id)
      |> Enum.reject(&is_nil(&1.spacecraft_type_id))
      |> Enum.filter(&(only == :all or &1.spacecraft_id in only))

    ids = Enum.map(spacecraft, & &1.spacecraft_id)
    profiles = profiles(organization_id, mission_id, spacecraft)
    overrides = Overrides.list(organization_id, mission_id, ids)
    rules = RoutingRuleStore.list_routing_rules_for_spacecrafts(organization_id, mission_id, ids)

    spacecraft
    |> Enum.flat_map(
      &drifts(&1, profiles[profile_pin(&1)], Map.get(overrides, &1.spacecraft_id, %{}), {
        transports,
        rules
      })
    )
    |> Enum.group_by(fn {profile, transport, differences, _sc} ->
      {profile, transport, differences}
    end)
    |> Enum.map(fn {{profile, transport, differences}, rows} ->
      %{
        profile: %{id: profile.spacecraft_type_id, name: profile.display_name},
        transport: %{id: transport.transport_id, name: transport.display_name},
        spacecraft_count: length(rows),
        differences: differences
      }
    end)
    |> Enum.sort_by(&{&1.profile.name, &1.transport.name})
  end

  @doc """
  Spacecraft (of `only`) on a profile whose transport framing can't be determined: no enabled
  inbound route, or no feeding transport with `ingress_metadata.frame_size`. DECISIONS #40:
  a framing change reaching them must HOLD, not pass silently. Grouped by profile and cause.
  """
  @spec unverified(String.t(), String.t(), [String.t()]) :: [map()]
  def unverified(organization_id, mission_id, only) do
    transports =
      organization_id
      |> TransportStore.list_transports(mission_id)
      |> Map.new(&{&1.transport_id, &1})

    spacecraft =
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id)
      |> Enum.filter(&(&1.spacecraft_id in only and not is_nil(&1.spacecraft_type_id)))

    rules =
      RoutingRuleStore.list_routing_rules_for_spacecrafts(
        organization_id,
        mission_id,
        Enum.map(spacecraft, & &1.spacecraft_id)
      )

    profiles = profiles(organization_id, mission_id, spacecraft)

    spacecraft
    |> Enum.flat_map(&unverified_cause(&1, profiles[profile_pin(&1)], {transports, rules}))
    |> Enum.group_by(fn {profile, cause} -> {profile, cause} end)
    |> Enum.map(fn {{profile, cause}, rows} ->
      %{profile: profile, cause: cause, spacecraft_count: length(rows)}
    end)
  end

  defp unverified_cause(_spacecraft, nil, _feeds), do: []

  defp unverified_cause(spacecraft, profile, feeds) do
    feeding = feeding_transports(spacecraft, feeds)

    cause =
      cond do
        feeding == [] ->
          :no_inbound_route

        not Enum.any?(feeding, &is_integer(ingress_metadata(&1)["frame_size"])) ->
          :no_ingress_metadata

        true ->
          nil
      end

    if cause,
      do: [{%{id: profile.spacecraft_type_id, name: profile.display_name}, cause}],
      else: []
  end

  defp profiles(organization_id, mission_id, spacecraft) do
    pins =
      for %{spacecraft_type_version: version} = craft <- spacecraft,
          is_integer(version) and version > 0,
          uniq: true,
          do: profile_pin(craft)

    {:ok, profiles} =
      SpacecraftTypeStore.fetch_spacecraft_type_versions_in_batches(
        organization_id,
        mission_id,
        pins
      )

    profiles
  end

  defp profile_pin(craft), do: {craft.spacecraft_type_id, craft.spacecraft_type_version}

  defp drifts(_spacecraft, nil, _overrides, _feeds), do: []

  defp drifts(spacecraft, profile, overrides, feeds) do
    framing = Effective.resolve(profile, overrides)["frame_parameters"]

    spacecraft
    |> feeding_transports(feeds)
    |> Enum.flat_map(&transport_drift(&1, profile, framing, spacecraft))
  end

  # The spacecraft's routing rules come preloaded for the whole set (one query, not one each).
  defp feeding_transports(spacecraft, {transports, rules}) do
    rules
    |> Map.get(spacecraft.spacecraft_id, [])
    |> Enum.filter(&(&1.enabled? and &1.direction in [:inbound, :bidirectional]))
    |> Enum.map(&Map.get(transports, &1.transport_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.transport_id)
  end

  defp transport_drift(transport, profile, framing, spacecraft) do
    case differences(framing, ingress_metadata(transport)) do
      [] -> []
      differences -> [{profile, transport, differences, spacecraft.spacecraft_id}]
    end
  end

  defp differences(framing, ingress) do
    for {field, default} <- @fields,
        profile_value = Map.get(framing, field, default),
        transport_value = Map.get(ingress, field, default),
        not is_nil(profile_value),
        profile_value != transport_value do
      %{
        path: "frame_parameters." <> field,
        profile_value: profile_value,
        transport_value: transport_value
      }
    end
  end

  defp ingress_metadata(transport) do
    case transport.configuration do
      %{"ingress_metadata" => %{} = metadata} -> metadata
      _ -> %{}
    end
  end
end
