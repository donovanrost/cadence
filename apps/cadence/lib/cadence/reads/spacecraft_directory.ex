defmodule Cadence.Reads.SpacecraftDirectory do
  @moduledoc """
  The Setup spacecraft directory: identity, profile binding, routing coverage
  and readiness per spacecraft, unpaginated.

  `ready` means the spacecraft has a SCID, a profile and at least one active,
  enabled routing rule. Fleet geometry and `norad_id` come from spacecraft
  metadata until they become first-class fields. Callers authorize first.
  """

  alias Cadence.Comms.RoutingRule
  alias Cadence.Configuration.ChangeSetStore
  alias Cadence.Reads.FleetStatus
  alias Cadence.Reads.OperationalState
  alias Cadence.Reads.SpacecraftMetadata
  alias Cadence.Spacecraft
  alias Cadence.Spacecraft.StagedScids
  alias Cadence.SpacecraftType

  @spec load(binary(), binary()) :: [map()]
  def load(organization_id, mission_id),
    do: organization_id |> index(mission_id) |> Map.fetch!(:spacecraft)

  @doc """
  The directory plus `telemetry: :ok | :degraded`: degraded when the durable history store
  didn't answer in time, so `last_received_at` comes from live values only (api-ops 17deb3c1)
  and may be missing for spacecraft not heard since the last restart.
  """
  @spec index(binary(), binary()) :: %{spacecraft: [map()], telemetry: :ok | :degraded}
  def index(organization_id, mission_id) do
    {last_received, telemetry} =
      FleetStatus.last_received_with_status(organization_id, mission_id)

    %{
      spacecraft:
        build(%{
          spacecraft: Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id),
          profiles:
            Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission_id),
          routing_rules: OperationalState.list_routing_rules(organization_id, mission_id),
          last_received: last_received
        }),
      telemetry: telemetry
    }
    |> Map.merge(scids(organization_id, mission_id))
  end

  # S9 (#313, U20): the SCIDs a new spacecraft can't take, and the one to suggest.
  defp scids(organization_id, mission_id) do
    in_use = StagedScids.in_use(organization_id, mission_id, active_staged_ops(mission_id))
    %{scids_in_use: in_use, next_free_scid: StagedScids.next_free(in_use)}
  end

  # The mission's open change set's staged ops, by any author (the read composes configuration;
  # StagedScids stays in the identity context).
  defp active_staged_ops(mission_id) do
    case ChangeSetStore.active(mission_id) do
      nil -> []
      set -> ChangeSetStore.staged_ops(set.change_set_id)
    end
  end

  @doc "Pure builder; see `load/2` for the inputs."
  @spec build(map()) :: [map()]
  def build(%{spacecraft: spacecraft} = input) do
    profiles = Map.new(Map.get(input, :profiles, []), &{&1.spacecraft_type_id, &1})
    last_received = Map.get(input, :last_received, %{})

    rule_counts =
      input
      |> Map.get(:routing_rules, [])
      |> Enum.filter(&usable_rule?/1)
      |> Enum.frequencies_by(& &1.spacecraft_id)

    spacecraft
    |> Enum.map(fn %Spacecraft{} = craft ->
      metadata = craft.metadata || %{}
      rule_count = Map.get(rule_counts, craft.spacecraft_id, 0)
      profile = profile(craft, profiles)

      %{
        id: craft.spacecraft_id,
        name: craft.display_name,
        scid: craft.scid,
        norad_id: SpacecraftMetadata.integer(metadata, "norad_id"),
        plane: SpacecraftMetadata.integer(metadata, "plane"),
        slot: SpacecraftMetadata.integer(metadata, "slot"),
        profile: profile,
        routing_rule_count: rule_count,
        ready: not is_nil(craft.scid) and not is_nil(profile) and rule_count > 0,
        last_received_at: Map.get(last_received, craft.spacecraft_id)
      }
    end)
    |> Enum.sort_by(&{&1.scid || :infinity, &1.name})
  end

  defp usable_rule?(%RoutingRule{lifecycle_state: :active, enabled?: true}), do: true
  defp usable_rule?(_rule), do: false

  defp profile(%Spacecraft{spacecraft_type_id: nil}, _profiles), do: nil

  defp profile(%Spacecraft{} = craft, profiles) do
    name =
      case Map.get(profiles, craft.spacecraft_type_id) do
        %SpacecraftType{display_name: name} -> name
        nil -> nil
      end

    %{id: craft.spacecraft_type_id, name: name, version: craft.spacecraft_type_version}
  end
end
