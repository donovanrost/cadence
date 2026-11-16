defmodule Cadence.Reads.LegacyRouteLabel do
  @moduledoc """
  The name a staged or applied `legacy_routing_rule` removal shows in the change list, preview
  and history (ux U79): `“<name>” · <spacecraft>`, or with no name the station form
  `INU · <spacecraft>`; with no spacecraft name the ` · …` part is dropped. Never an id. The
  console puts its own verb in front ('Remove older route …', 'Removed older route …').

  Built from the kind's document (`spacecraft_id`, `display_name`, `transport_id`): the live one
  while the rule is active, the revision's `before` once it's archived.
  """

  alias Cadence.Comms.GroundStationStore
  alias Cadence.Reads.OperationalState
  alias Cadence.SpacecraftStore

  @doc "Labels for documents keyed by entity id; a document without enough to name gets none."
  @spec labels(binary(), binary(), %{optional(binary()) => map()}) :: %{
          optional(binary()) => binary()
        }
  def labels(_organization_id, _mission_id, documents) when map_size(documents) == 0, do: %{}

  def labels(organization_id, mission_id, documents) do
    context = context(organization_id, mission_id)

    for {id, document} <- documents,
        is_map(document),
        label = label(document, context),
        into: %{},
        do: {id, label}
  end

  defp label(document, context) do
    craft = Map.get(context.spacecraft, document["spacecraft_id"])

    head =
      case document["display_name"] do
        name when is_binary(name) and name != "" -> "“#{name}”"
        _unnamed -> station_code(document["transport_id"], context)
      end

    [head, craft] |> Enum.reject(&blank?/1) |> join()
  end

  defp join([]), do: nil
  defp join(parts), do: Enum.join(parts, " · ")

  defp station_code(transport_id, context) do
    with %{ground_station_id: station_id} when is_binary(station_id) <-
           Map.get(context.transports, transport_id),
         %{code: code} when is_binary(code) <- Map.get(context.stations, station_id) do
      code
    else
      _unknown -> nil
    end
  end

  defp context(organization_id, mission_id) do
    %{
      spacecraft:
        organization_id
        |> SpacecraftStore.list_spacecraft(mission_id, include_archived: true)
        |> Map.new(&{&1.spacecraft_id, &1.display_name}),
      transports:
        organization_id
        |> OperationalState.list_transports(mission_id)
        |> Map.new(&{&1.transport_id, &1}),
      stations:
        organization_id
        |> GroundStationStore.list_ground_stations(mission_id)
        |> Map.new(&{&1.ground_station_id, &1})
    }
  end

  defp blank?(value), do: not is_binary(value) or value == ""
end
