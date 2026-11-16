defmodule Cadence.Comms.ConfigKinds.SpacecraftRoute do
  @moduledoc """
  Change-set kind for a spacecraft's own extra route (DECISIONS #3 "per-spacecraft overrides";
  profile-routing.md §2.2 `origin: spacecraft`; ux's "Extra route" override, lead 11-16).

  The same rule shape as a profile routing rule, scoped to one spacecraft: one station, its
  legs (direction + role), a name and a purpose label. It's how one craft gets a route its
  profile doesn't give it, for a recovery move or a test, without a profile version or a rollout.
  Each leg is one `origin: :spacecraft` route row, planned exactly like a profile route
  (`Cadence.Comms.RoutePlan.spacecraft_route/4`), with the entity's id in `profile_rule_id`.
  Route materialization leaves these rows alone; delete archives them.

  Document: `%{"spacecraft_id", "ground_station_id", "transport_id" (optional: the station's
  single transport that can carry each leg), "legs" => [%{"direction", "role"}], "display_name"
  (optional, `{station}`-style tokens), "purpose_label"}`. The spacecraft is fixed once created.
  A route the spacecraft already has from its profile (same transport, direction and role) is
  refused. Booked and running contacts keep the routes they were booked with.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Comms.{GroundStationStore, RoutePlan, RoutingRuleStore, TransportStore}
  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.SpacecraftStore

  @fields ~w(spacecraft_id ground_station_id transport_id legs display_name purpose_label)
  @directions ~w(downlink uplink)
  @roles ~w(primary candidate contributing)

  @impl true
  def kind, do: "spacecraft_route"

  @impl true
  def id_prefix, do: "spacecraft_route"

  @impl true
  def load(organization_id, mission_id, ids) do
    organization_id
    |> RoutingRuleStore.list_routing_rules(mission_id)
    |> Enum.filter(&(&1.origin == :spacecraft and &1.profile_rule_id in ids))
    |> Enum.group_by(& &1.profile_rule_id)
    |> Map.new(fn {id, rows} -> {id, document(rows)} end)
  end

  @impl true
  def normalize(:delete, _id, nil), do: {:ok, nil}

  def normalize(_action, _id, %{} = document) do
    document =
      Map.update(document, "legs", [], fn legs ->
        if is_list(legs), do: Enum.map(legs, &default_role/1), else: legs
      end)

    errors =
      F.only(document, @fields) ++
        F.text(document, "spacecraft_id", 1..240, required: true, label: "Spacecraft") ++
        F.text(document, "ground_station_id", 1..240, required: true, label: "Station") ++
        F.text(document, "transport_id", 1..240, label: "Transport") ++
        F.text(document, "display_name", 1..200, label: "Name") ++
        F.text(document, "purpose_label", 1..200, label: "Purpose") ++
        leg_errors(document["legs"])

    F.result(document, errors)
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Enter the spacecraft, station and legs")]}

  @impl true
  def validate(_organization_id, _mission_id, :delete, _id, _previous, nil), do: :ok

  def validate(_org, _mission, :update, _id, %{"spacecraft_id" => from}, %{"spacecraft_id" => to})
      when from != to,
      do: {:error, [F.error("spacecraft_id", "An extra route stays on its spacecraft")]}

  def validate(organization_id, mission_id, _action, id, _previous, proposed) do
    with {:ok, spacecraft} <- spacecraft(organization_id, mission_id, proposed),
         {:ok, routes} <- plan(organization_id, mission_id, spacecraft, id, proposed) do
      not_from_profile(organization_id, spacecraft, routes)
    end
  end

  @impl true
  def write(
        organization_id,
        mission_id,
        :delete,
        id,
        %{"spacecraft_id" => spacecraft_id},
        nil,
        _o
      ) do
    organization_id
    |> own_rows(mission_id, spacecraft_id, id)
    |> archive(organization_id)
    |> case do
      :ok -> {:ok, nil, []}
      {:error, reason} -> {:error, reason}
    end
  end

  def write(organization_id, mission_id, _action, id, _previous, proposed, _options) do
    with {:ok, spacecraft} <- spacecraft(organization_id, mission_id, proposed),
         {:ok, routes} <- plan(organization_id, mission_id, spacecraft, id, proposed),
         :ok <- put_routes(organization_id, routes),
         wanted = MapSet.new(routes, & &1.routing_rule_id),
         :ok <-
           organization_id
           |> own_rows(mission_id, spacecraft.spacecraft_id, id)
           |> Enum.reject(&MapSet.member?(wanted, &1.routing_rule_id))
           |> archive(organization_id) do
      {:ok, document(own_rows(organization_id, mission_id, spacecraft.spacecraft_id, id)), []}
    end
  end

  @impl true
  def summary(:create, nil, proposed), do: "Add an extra route for #{proposed["spacecraft_id"]}"
  def summary(:delete, previous, nil), do: "Remove extra route #{previous["display_name"]}"
  def summary(:update, previous, _proposed), do: "Edit extra route #{previous["display_name"]}"

  @impl true
  def runtime_impact(_action, _previous, _proposed), do: :contacts

  defp spacecraft(organization_id, mission_id, %{"spacecraft_id" => spacecraft_id}) do
    case SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id) do
      {:ok, spacecraft} -> {:ok, spacecraft}
      {:error, _missing} -> {:error, [F.error("spacecraft_id", "That spacecraft doesn't exist")]}
    end
  end

  defp plan(organization_id, mission_id, spacecraft, id, proposed) do
    context =
      RoutePlan.context(
        GroundStationStore.list_ground_stations(organization_id, mission_id),
        TransportStore.list_transports(organization_id, mission_id)
      )

    RoutePlan.spacecraft_route(spacecraft, id, proposed, context)
  end

  # ux's words: a route the profile already gives this spacecraft isn't an extra one.
  defp not_from_profile(organization_id, spacecraft, routes) do
    profile =
      organization_id
      |> RoutingRuleStore.list_routing_rules_for_spacecraft(
        spacecraft.mission_id,
        spacecraft.spacecraft_id
      )
      |> Enum.filter(&(&1.origin == :profile))
      |> MapSet.new(&{&1.transport_id, &1.direction, &1.role})

    if Enum.any?(routes, &MapSet.member?(profile, {&1.transport_id, &1.direction, &1.role})),
      do:
        {:error,
         [
           F.error(
             "ground_station_id",
             "#{spacecraft.display_name} already has this route from its profile."
           )
         ]},
      else: :ok
  end

  defp put_routes(organization_id, routes) do
    Enum.reduce_while(routes, :ok, fn route, :ok ->
      case RoutingRuleStore.put_route(organization_id, route) do
        {:ok, _rule, _change} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp own_rows(organization_id, mission_id, spacecraft_id, id),
    do:
      organization_id
      |> RoutingRuleStore.list_routing_rules_for_spacecraft(mission_id, spacecraft_id)
      |> Enum.filter(&(&1.origin == :spacecraft and &1.profile_rule_id == id))

  defp archive(rows, organization_id) do
    Enum.reduce_while(rows, :ok, fn row, :ok ->
      case RoutingRuleStore.archive_routing_rule(
             organization_id,
             row.mission_id,
             row.routing_rule_id
           ) do
        {:ok, _archived} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  # What's live, as a document: the rows share the station, transport, name and label.
  defp document([first | _] = rows),
    do: %{
      "spacecraft_id" => first.spacecraft_id,
      "ground_station_id" => first.ground_station_id,
      "transport_id" => first.transport_id,
      "display_name" => first.display_name,
      "purpose_label" => first.purpose_label,
      "legs" =>
        rows
        |> Enum.map(&%{"direction" => &1.leg_direction, "role" => Atom.to_string(&1.role)})
        |> Enum.sort_by(& &1["direction"])
    }

  defp document([]), do: nil

  defp default_role(%{} = leg), do: Map.put_new(leg, "role", "primary")
  defp default_role(leg), do: leg

  defp leg_errors(legs) when is_list(legs) and legs != [] do
    directions = Enum.map(legs, &(is_map(&1) && &1["direction"]))

    cond do
      not Enum.all?(legs, &valid_leg?/1) ->
        [F.error("legs", "Each leg is a direction (downlink, uplink) and a role")]

      length(Enum.uniq(directions)) != length(directions) ->
        [F.error("legs", "Each direction once")]

      true ->
        []
    end
  end

  defp leg_errors(_legs), do: [F.error("legs", "Add at least one leg")]

  defp valid_leg?(%{"direction" => direction, "role" => role} = leg),
    do: map_size(leg) == 2 and direction in @directions and role in @roles

  defp valid_leg?(_leg), do: false
end
