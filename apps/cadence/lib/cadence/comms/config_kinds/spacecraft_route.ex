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
  single transport that can carry each leg), "downlink", "uplink" (each `none`, `primary`,
  `candidate` or `contributing`; defaults primary and none; at least one not none), "display_name" (optional,
  `{station}`-style tokens), "purpose_label"}`. The two direction fields are the legs: the kind
  maps them server-side (lead, fe-setup: the console form stays fully generated), and a loaded
  document exposes the same paths. The spacecraft is fixed once created.
  A route the spacecraft already has from its profile (same transport, direction and role) is
  refused. Booked and running contacts keep the routes they were booked with.
  """

  @behaviour Cadence.Platform.ConfigKind

  alias Cadence.Comms.{GroundStationStore, RoutePlan, RoutingRuleStore, TransportStore}
  alias Cadence.Platform.ConfigFields, as: F
  alias Cadence.SpacecraftStore

  @fields ~w(spacecraft_id ground_station_id transport_id downlink uplink display_name
             purpose_label)
  @directions ~w(downlink uplink)
  @settings ~w(none primary candidate contributing)

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
    document = document |> Map.put_new("downlink", "primary") |> Map.put_new("uplink", "none")

    errors =
      F.only(document, @fields) ++
        F.text(document, "spacecraft_id", 1..240, required: true, label: "Spacecraft") ++
        station_errors(document) ++
        F.text(document, "transport_id", 1..240, label: "Transport") ++
        F.text(document, "display_name", 1..200, label: "Name") ++
        F.text(document, "purpose_label", 1..200, label: "Purpose") ++
        F.one_of(document, "downlink", @settings, required: true, label: "Downlink") ++
        F.one_of(document, "uplink", @settings, required: true, label: "Uplink") ++
        leg_errors(document)

    F.result(document, errors)
  end

  def normalize(_action, _id, _document),
    do: {:error, [F.error("", "Enter the spacecraft, station and directions")]}

  @impl true
  def validate(_organization_id, _mission_id, :delete, _id, _previous, nil), do: :ok

  def validate(_org, _mission, :update, _id, %{"spacecraft_id" => from}, %{"spacecraft_id" => to})
      when from != to,
      do:
        {:error,
         [
           F.error(
             "spacecraft_id",
             "An extra route can't move to another spacecraft; remove it and add one there"
           )
         ]}

  def validate(organization_id, mission_id, _action, id, _previous, proposed) do
    context = context(organization_id, mission_id)

    with {:ok, spacecraft} <- spacecraft(organization_id, mission_id, proposed),
         :ok <- transport_errors(context, proposed),
         {:ok, routes} <- plan(context, spacecraft, id, proposed) do
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
         {:ok, routes} <-
           plan(context(organization_id, mission_id), spacecraft, id, proposed),
         :ok <- put_routes(organization_id, Enum.map(routes, &authored(&1, proposed))),
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
  # ux U25: names, never ids. A new route's name is rendered only when it's written, so a create
  # without one says so plainly; previews and revisions name it from the stored document.
  def summary(:create, nil, %{"display_name" => name}) when is_binary(name),
    do: "Add extra route #{name}"

  def summary(:create, nil, _proposed), do: "Add an extra route"
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

  defp context(organization_id, mission_id),
    do:
      RoutePlan.context(
        GroundStationStore.list_ground_stations(organization_id, mission_id),
        TransportStore.list_transports(organization_id, mission_id)
      )

  defp plan(context, spacecraft, id, proposed),
    do:
      RoutePlan.spacecraft_route(
        spacecraft,
        id,
        Map.put(proposed, "legs", legs(proposed)),
        context
      )

  # ux's words for the transport choice, checked before planning: the named transport must be at
  # the station and carry every leg; with none named, each leg needs exactly one at the station
  # (none at all is RoutePlan's "has no active ... transport").
  defp transport_errors(context, proposed) do
    station = Map.get(context.stations, proposed["ground_station_id"])

    errors =
      case {station, proposed["transport_id"]} do
        {nil, _transport} -> []
        {station, nil} -> ambiguous(context, station, legs(proposed))
        {station, id} -> named(Map.get(context.transports, id), station, legs(proposed))
      end

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp ambiguous(context, station, legs) do
    for %{"direction" => direction} <- legs,
        count = carriers(context, station, direction),
        count > 1,
        do:
          F.error(
            "transport_id",
            "#{station.display_name} has #{count} transports that can carry #{direction}; choose one"
          )
  end

  defp carriers(context, station, direction),
    do:
      context.transports_by_station
      |> Map.get(station.ground_station_id, [])
      |> Enum.count(&carries?(&1, direction))

  defp named(nil, _station, _legs), do: [F.error("transport_id", "That transport doesn't exist")]

  defp named(transport, station, legs) do
    if transport.ground_station_id == station.ground_station_id,
      do:
        for(
          %{"direction" => direction} <- legs,
          not carries?(transport, direction),
          do: F.error("transport_id", "#{transport.display_name} can't carry #{direction}")
        ),
      else: [
        F.error("transport_id", "#{transport.display_name} isn't at #{station.display_name}")
      ]
  end

  defp carries?(%{direction_capability: :bidirectional}, _direction), do: true
  defp carries?(%{direction_capability: :inbound}, "downlink"), do: true
  defp carries?(%{direction_capability: :outbound}, "uplink"), do: true
  defp carries?(_transport, _direction), do: false

  defp station_errors(%{"ground_station_id" => id}) when is_binary(id) and id != "", do: []
  defp station_errors(_document), do: [F.error("ground_station_id", "Choose a station")]

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
      # Its written document rides on every row, so an edit that resolves to the same rows still
      # stores what the operator wrote.
      case RoutingRuleStore.put_route(organization_id, route, also: [:metadata]) do
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

  # The route as the operator WROTE it is the source (lead, fe-setup's catch): the rows are its
  # resolved output (the station's transport per leg, the rendered name). Each row keeps the
  # written document, so load/3 returns exactly what was staged: an empty transport stays empty,
  # two legs on two different station transports stay unpinned, a name template stays a template.
  @authored_key "authored_document"

  defp authored(route, proposed),
    do: %{route | metadata: Map.put(route.metadata || %{}, @authored_key, written(proposed))}

  defp written(proposed), do: Map.take(proposed, @fields)

  defp document([%{metadata: %{@authored_key => %{} = written}} | _rows]), do: written

  # Rows written before the document was kept: rebuilt from the rows (resolved values).
  defp document([first | _] = rows),
    do: %{
      "spacecraft_id" => first.spacecraft_id,
      "ground_station_id" => first.ground_station_id,
      "transport_id" => first.transport_id,
      "display_name" => first.display_name,
      "purpose_label" => first.purpose_label,
      "downlink" => setting(rows, "downlink"),
      "uplink" => setting(rows, "uplink")
    }

  defp document([]), do: nil

  defp setting(rows, direction) do
    case Enum.find(rows, &(&1.leg_direction == direction)) do
      nil -> "none"
      row -> Atom.to_string(row.role)
    end
  end

  # The legs the two direction fields stand for.
  defp legs(document),
    do:
      for(
        direction <- @directions,
        (role = document[direction]) not in [nil, "none"],
        do: %{"direction" => direction, "role" => role}
      )

  defp leg_errors(%{"downlink" => "none", "uplink" => "none"}),
    do: [F.error("downlink", "Choose a role for downlink, uplink or both")]

  defp leg_errors(_document), do: []
end
