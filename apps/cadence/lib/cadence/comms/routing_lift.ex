defmodule Cadence.Comms.RoutingLift do
  @moduledoc """
  Lifts legacy per-spacecraft routing rules into profile routing rules
  (`docs/apogee/domain/profile-routing.md` §6B). Computes change-set ops only; nothing changes
  until the change set is reviewed and applied.

  For each profile, over the spacecraft on its current version (excluding spacecraft whose
  framing is governed by a configuration review, which keep their pins):

  1. Each legacy rule gives signatures `{transport, direction, role}` (bidirectional gives two).
  2. A signature held by at least half of those spacecraft, on a transport linked to a ground
     station, becomes a station of the lifted rule for its `(direction, role)`.
  3. A spacecraft missing a lifted station gets an `excluded_stations` override. Signatures not
     lifted stay as legacy rules.

  On apply, the materializer creates the profile routes and retires every legacy rule a profile
  route now covers, so each spacecraft keeps the same `(transport, direction, role)` set.
  """

  alias Cadence.Comms.{RoutingRuleStore, TransportStore}
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftTypeStore

  @governed_key "spacecraft_configuration_revision_id"

  @spec ops(String.t(), String.t()) :: {:ok, %{ops: [map()], summary: map()}}
  def ops(organization_id, mission_id) do
    transports =
      organization_id
      |> TransportStore.list_transports(mission_id)
      |> Map.new(&{&1.transport_id, &1})

    plans =
      organization_id
      |> SpacecraftTypeStore.list_spacecraft_types(mission_id)
      |> Enum.map(&plan_profile(organization_id, mission_id, &1, transports))
      |> Enum.reject(&(&1.rules == []))

    ops = Enum.flat_map(plans, & &1.ops)

    {:ok,
     %{
       ops: ops,
       summary: %{
         profiles: length(plans),
         rules: plans |> Enum.map(&length(&1.rules)) |> Enum.sum(),
         overrides: Enum.count(ops, &(&1.kind == "spacecraft_override"))
       }
     }}
  end

  defp plan_profile(organization_id, mission_id, profile, transports) do
    spacecraft =
      organization_id
      |> SpacecraftStore.list_pinned_to_profile(mission_id, profile.spacecraft_type_id,
        version: profile.version
      )
      |> Enum.reject(&is_binary(Map.get(&1.metadata || %{}, @governed_key)))

    signatures =
      Map.new(spacecraft, fn sc ->
        {sc.spacecraft_id, legacy_signatures(organization_id, mission_id, sc.spacecraft_id)}
      end)

    rules = lifted_rules(signatures, length(spacecraft), transports, profile)

    %{
      rules: rules,
      ops:
        if(rules == [],
          do: [],
          else: [profile_op(profile, rules) | override_ops(signatures, rules)]
        )
    }
  end

  defp legacy_signatures(organization_id, mission_id, spacecraft_id) do
    organization_id
    |> RoutingRuleStore.list_routing_rules_for_spacecraft(mission_id, spacecraft_id)
    |> Enum.filter(&(&1.origin == :legacy and &1.enabled?))
    |> Enum.flat_map(fn rule ->
      for direction <- directions(rule.direction),
          do: %{
            transport_id: rule.transport_id,
            direction: direction,
            role: Atom.to_string(rule.role),
            label: rule.purpose_label
          }
    end)
  end

  defp lifted_rules(_signatures, 0, _transports, _profile), do: []

  defp lifted_rules(signatures, fleet, transports, profile) do
    existing = MapSet.new(profile.routing_rules, & &1["id"])

    signatures
    |> Map.values()
    |> Enum.flat_map(&Enum.uniq_by(&1, fn s -> {s.transport_id, s.direction, s.role} end))
    |> Enum.group_by(&{&1.transport_id, &1.direction, &1.role})
    |> Enum.filter(fn {{transport_id, _d, _r}, held} ->
      length(held) * 2 >= fleet and station_of(transports, transport_id)
    end)
    |> Enum.group_by(fn {{_t, direction, role}, _held} -> {direction, role} end)
    |> Enum.map(fn {{direction, role}, entries} ->
      build_rule(direction, role, entries, transports)
    end)
    |> Enum.reject(&MapSet.member?(existing, &1["id"]))
    |> Enum.sort_by(& &1["id"])
  end

  # One station per rule: when two transports reach the same station, the more common one is
  # lifted and the other stays a legacy rule.
  defp build_rule(direction, role, entries, transports) do
    stations =
      entries
      |> Enum.sort_by(fn {_key, held} -> -length(held) end)
      |> Enum.uniq_by(fn {{transport_id, _, _}, _} -> station_of(transports, transport_id) end)
      |> Enum.map(fn {{transport_id, _, _}, _held} ->
        %{
          "ground_station_id" => station_of(transports, transport_id),
          "transport_id" => transport_id
        }
      end)
      |> Enum.sort_by(& &1["ground_station_id"])

    label =
      entries
      |> Enum.flat_map(fn {_key, held} -> Enum.map(held, & &1.label) end)
      |> Enum.frequencies()
      |> Enum.max_by(&elem(&1, 1))
      |> elem(0)

    %{
      "id" => "lifted-#{direction}-#{role}",
      "label" => label,
      "name_template" => "{station} · {spacecraft}",
      "enabled" => true,
      "stations" => stations,
      "legs" => [%{"direction" => direction, "role" => role}]
    }
  end

  defp profile_op(profile, rules) do
    %{
      kind: "spacecraft_profile",
      action: :update,
      entity_id: profile.spacecraft_type_id,
      changes: [%{path: "routing_rules", value: profile.routing_rules ++ rules}],
      options: %{"rollout" => "all"}
    }
  end

  defp override_ops(signatures, rules) do
    signatures
    |> Enum.sort()
    |> Enum.flat_map(fn {spacecraft_id, held} ->
      changes =
        for rule <- rules,
            missing = missing_stations(rule, held),
            missing != [] do
          %{
            path: "routing/#{rule["id"]}/excluded_stations",
            value: %{"value" => missing, "reason" => "Lifted from per-spacecraft routing rules"}
          }
        end

      if changes == [],
        do: [],
        else: [
          %{
            kind: "spacecraft_override",
            action: :update,
            entity_id: spacecraft_id,
            changes: changes
          }
        ]
    end)
  end

  defp missing_stations(rule, held) do
    [%{"direction" => direction, "role" => role}] = rule["legs"]
    have = MapSet.new(held, &{&1.transport_id, &1.direction, &1.role})

    for station <- rule["stations"],
        not MapSet.member?(have, {station["transport_id"], direction, role}),
        do: station["ground_station_id"]
  end

  defp station_of(transports, transport_id) do
    case Map.get(transports, transport_id) do
      %{ground_station_id: station} when is_binary(station) -> station
      _ -> nil
    end
  end

  defp directions(:bidirectional), do: ["downlink", "uplink"]
  defp directions(:inbound), do: ["downlink"]
  defp directions(:outbound), do: ["uplink"]
end
