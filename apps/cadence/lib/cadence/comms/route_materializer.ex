defmodule Cadence.Comms.RouteMaterializer do
  @moduledoc """
  Brings spacecraft's `origin: profile` routes in line with their pinned profile version, their
  overrides, and the mission's stations and transports. Only changed routes are written; routes
  no longer wanted are archived (their materialized paths retire with them). Spacecraft-local
  and legacy routes are left alone.

  Runs inside the caller's transaction (change-set apply or preview). Uses only `Repo`.
  """

  alias Cadence.Comms.{GroundStationStore, RoutePlan, RoutingRuleStore, TransportStore}
  alias Cadence.SpacecraftStore
  alias Cadence.SpacecraftStore.Overrides
  alias Cadence.SpacecraftType.Effective
  alias Cadence.SpacecraftTypeStore

  @type change :: %{spacecraft_id: String.t(), previous: map(), proposed: map()}

  @doc "Returns one change per spacecraft whose routes changed, or field errors."
  @spec materialize(String.t(), String.t(), [String.t()]) :: {:ok, [change()]} | {:error, [map()]}
  def materialize(_organization_id, _mission_id, []), do: {:ok, []}

  def materialize(organization_id, mission_id, spacecraft_ids) do
    context =
      RoutePlan.context(
        GroundStationStore.list_ground_stations(organization_id, mission_id),
        TransportStore.list_transports(organization_id, mission_id)
      )

    overrides = Overrides.list(organization_id, mission_id, spacecraft_ids)

    spacecraft_ids
    |> Enum.uniq()
    |> Enum.chunk_every(1_000)
    |> Enum.flat_map(fn ids ->
      {:ok, found} =
        SpacecraftStore.fetch_spacecrafts_in_batches(organization_id, mission_id, ids)

      rules =
        RoutingRuleStore.list_routing_rules_for_spacecrafts(organization_id, mission_id, ids)

      Enum.map(Map.values(found), &{&1, Map.fetch!(rules, &1.spacecraft_id)})
    end)
    |> Enum.reduce_while({:ok, []}, fn {spacecraft, before}, {:ok, changes} ->
      case reconcile(
             organization_id,
             spacecraft,
             before,
             Map.get(overrides, spacecraft.spacecraft_id, %{}),
             context
           ) do
        {:ok, nil} -> {:cont, {:ok, changes}}
        {:ok, change} -> {:cont, {:ok, [change | changes]}}
        {:error, errors} -> {:halt, {:error, errors}}
      end
    end)
    |> case do
      {:ok, changes} -> {:ok, Enum.reverse(changes)}
      error -> error
    end
  end

  @doc "A spacecraft's profile routes as a ledger document."
  @spec document(String.t(), String.t(), String.t()) :: map()
  def document(organization_id, mission_id, spacecraft_id) do
    organization_id
    |> RoutingRuleStore.list_routing_rules_for_spacecraft(mission_id, spacecraft_id)
    |> to_document()
  end

  # `before`: the spacecraft's rules, preloaded for its chunk. They're read again only when this
  # reconcile changed something (a route written, archived or retired); otherwise nothing moved.
  defp reconcile(organization_id, spacecraft, before, overrides, context) do
    mission_id = spacecraft.mission_id
    existing = Enum.filter(before, &(&1.origin == :profile))

    with {:ok, desired} <- desired(organization_id, spacecraft, overrides, context),
         {:ok, written} <- write(organization_id, desired),
         {:ok, archived} <- archive_unwanted(organization_id, existing, desired),
         {:ok, retired} <- retire_superseded(organization_id, before, desired) do
      after_routes =
        if written or archived or retired,
          do:
            RoutingRuleStore.list_routing_rules_for_spacecraft(
              organization_id,
              mission_id,
              spacecraft.spacecraft_id
            ),
          else: before

      previous = to_document(before)
      proposed = to_document(after_routes)

      if previous == proposed,
        do: {:ok, nil},
        else:
          {:ok,
           %{spacecraft_id: spacecraft.spacecraft_id, previous: previous, proposed: proposed}}
    end
  end

  defp desired(_organization_id, %{spacecraft_type_id: nil}, _overrides, _context), do: {:ok, []}

  defp desired(organization_id, spacecraft, overrides, context) do
    case SpacecraftTypeStore.fetch_spacecraft_type_version(
           organization_id,
           spacecraft.mission_id,
           spacecraft.spacecraft_type_id,
           spacecraft.spacecraft_type_version
         ) do
      {:ok, profile} ->
        profile
        |> Effective.resolve(overrides)
        |> then(
          &RoutePlan.plan(spacecraft, &1, profile.spacecraft_type_id, profile.version, context)
        )
        |> prefix_errors(spacecraft)

      {:error, _missing} ->
        {:ok, []}
    end
  end

  defp prefix_errors({:error, errors}, spacecraft),
    do: {:error, Enum.map(errors, &%{&1 | message: "#{spacecraft.display_name}: #{&1.message}"})}

  defp prefix_errors(ok, _spacecraft), do: ok

  # {:ok, changed?}: whether any route was created or updated.
  defp write(organization_id, desired) do
    Enum.reduce_while(desired, {:ok, false}, fn route, {:ok, changed} ->
      case RoutingRuleStore.put_route(organization_id, route) do
        {:ok, _rule, change} ->
          {:cont, {:ok, changed or change != :unchanged}}

        {:error, reason} ->
          {:halt,
           {:error, [%{path: "routing", message: "Couldn't save route: #{inspect(reason)}"}]}}
      end
    end)
  end

  defp archive_unwanted(organization_id, existing, desired) do
    wanted = MapSet.new(desired, & &1.routing_rule_id)
    unwanted = Enum.reject(existing, &MapSet.member?(wanted, &1.routing_rule_id))

    Enum.each(
      unwanted,
      &RoutingRuleStore.archive_routing_rule(organization_id, &1.mission_id, &1.routing_rule_id)
    )

    {:ok, unwanted != []}
  end

  # A legacy per-spacecraft rule that a profile route now covers (same transport, direction and
  # role) is retired, so the lift into profile rules never leaves two live copies of a route.
  # A bidirectional rule is retired once both of its directions are covered.
  defp retire_superseded(_organization_id, _before, []), do: {:ok, false}

  # `before`: the spacecraft's rules from before this reconcile's writes. Those writes are profile
  # routes only, so its legacy rules are as they were. {:ok, retired?}.
  defp retire_superseded(organization_id, before, desired) do
    covered = MapSet.new(desired, &{&1.transport_id, &1.direction, &1.role})

    superseded =
      Enum.filter(before, fn rule ->
        rule.origin == :legacy and rule.enabled? and
          rule
          |> directions()
          |> Enum.all?(&MapSet.member?(covered, {rule.transport_id, &1, rule.role}))
      end)

    Enum.each(
      superseded,
      &RoutingRuleStore.archive_routing_rule(
        organization_id,
        &1.mission_id,
        &1.routing_rule_id,
        %{
          "superseded_by_profile_route" => true
        }
      )
    )

    {:ok, superseded != []}
  end

  defp directions(%{direction: :bidirectional}), do: [:inbound, :outbound]
  defp directions(%{direction: direction}), do: [direction]

  defp to_document(routes) do
    %{
      "routes" =>
        routes
        |> Enum.map(fn route ->
          %{
            "id" => route.routing_rule_id,
            "name" => route.display_name,
            "rule" => route.profile_rule_id,
            "station" => route.ground_station_id,
            "leg" => route.leg_direction,
            "transport" => "#{route.transport_id}@#{route.transport_version}",
            "role" => Atom.to_string(route.role),
            "origin" => Atom.to_string(route.origin)
          }
        end)
        |> Enum.sort_by(& &1["id"])
    }
  end
end
