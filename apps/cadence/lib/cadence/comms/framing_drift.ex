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

  @spec audit(String.t(), String.t()) :: [item()]
  def audit(organization_id, mission_id) do
    transports =
      organization_id
      |> TransportStore.list_transports(mission_id)
      |> Map.new(&{&1.transport_id, &1})

    spacecraft =
      organization_id
      |> SpacecraftStore.list_spacecraft(mission_id)
      |> Enum.reject(&is_nil(&1.spacecraft_type_id))

    overrides =
      Overrides.list(organization_id, mission_id, Enum.map(spacecraft, & &1.spacecraft_id))

    spacecraft
    |> Enum.flat_map(
      &drifts(organization_id, &1, Map.get(overrides, &1.spacecraft_id, %{}), transports)
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

  defp drifts(organization_id, spacecraft, overrides, transports) do
    case SpacecraftTypeStore.fetch_spacecraft_type_version(
           organization_id,
           spacecraft.mission_id,
           spacecraft.spacecraft_type_id,
           spacecraft.spacecraft_type_version
         ) do
      {:ok, profile} ->
        framing = Effective.resolve(profile, overrides)["frame_parameters"]

        organization_id
        |> feeding_transports(spacecraft, transports)
        |> Enum.flat_map(&transport_drift(&1, profile, framing, spacecraft))

      {:error, _missing} ->
        []
    end
  end

  defp feeding_transports(organization_id, spacecraft, transports) do
    organization_id
    |> RoutingRuleStore.list_routing_rules_for_spacecraft(
      spacecraft.mission_id,
      spacecraft.spacecraft_id
    )
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
