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
  alias Cadence.Comms.RoutingRuleStore.Batch
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
    {documents, _rows} = load_batch(organization_id, mission_id, ids)
    documents
  end

  @impl true
  def batchable?(op), do: replaces(Map.get(op.payload, "options", %{})) == []

  @impl true
  def load_batch(organization_id, mission_id, ids) do
    rows = RoutingRuleStore.extra_route_rows(organization_id, mission_id, ids)

    documents =
      for {id, legs} <- rows,
          current = document(active_rows(legs)),
          current != nil,
          into: %{},
          do: {id, current}

    {documents, rows}
  end

  @impl true
  def write_batch(org, mission, transitions, rows) do
    with {:ok, context} <- load_batch_context(org, mission, transitions),
         {outcomes, planned} = plan_batch(org, transitions, rows, context),
         :ok <- Batch.persist(org, mission, Enum.reverse(planned), context) do
      {:ok, outcomes}
    end
  end

  defp load_batch_context(org, mission, transitions) do
    documents = Enum.map(transitions, & &1.proposed) |> Enum.reject(&is_nil/1)
    spacecraft_ids = Enum.map(documents, & &1["spacecraft_id"]) |> Enum.reject(&is_nil/1)
    station_ids = Enum.map(documents, & &1["ground_station_id"]) |> Enum.reject(&is_nil/1)
    transport_ids = Enum.map(documents, & &1["transport_id"]) |> Enum.reject(&is_nil/1)

    with {:ok, spacecraft} <-
           SpacecraftStore.fetch_spacecrafts_in_batches(org, mission, spacecraft_ids) do
      context =
        GroundStationStore.fetch_ground_stations(org, mission, station_ids)
        |> RoutePlan.context(
          TransportStore.route_transports(org, mission, station_ids, transport_ids)
        )
        |> Map.put(:spacecraft, spacecraft)
        |> Map.put(
          :profile_choices,
          RoutingRuleStore.profile_choices(org, mission, spacecraft_ids)
        )

      {:ok, context}
    end
  end

  defp plan_batch(org, transitions, rows, context) do
    Enum.map_reduce(transitions, [], fn change, planned ->
      case plan_batch_change(org, change, context, Map.get(rows, change.id, [])) do
        {:ok, stored, legs} -> {{:ok, stored}, Enum.reverse(legs, planned)}
        {:error, fields} -> {{:invalid, fields}, planned}
      end
    end)
  end

  defp plan_batch_change(_org, %{action: :delete}, _context, rows) do
    {:ok, nil, Enum.map(active_rows(rows), &RoutingRuleStore.planned_archive/1)}
  end

  defp plan_batch_change(
         _org,
         %{
           action: :update,
           current: %{"spacecraft_id" => from},
           proposed: %{"spacecraft_id" => to}
         },
         _context,
         _rows
       )
       when from != to,
       do: cannot_move()

  defp plan_batch_change(org, change, context, rows) do
    with {:ok, spacecraft} <- batch_spacecraft(context, change.proposed),
         :ok <- transport_errors(context, change.proposed),
         {:ok, routes} <- plan(context, spacecraft, change.id, change.proposed),
         :ok <-
           check_profile(
             spacecraft,
             routes,
             Map.get(context.profile_choices, spacecraft.spacecraft_id, MapSet.new())
           ) do
      {:ok, written(change.proposed), plan_legs(org, change.proposed, rows, routes)}
    end
  end

  defp plan_legs(org, document, rows, routes) do
    current = Map.new(rows, &{&1.routing_rule_id, &1})
    wanted = MapSet.new(routes, & &1.routing_rule_id)

    updates =
      for route <- routes,
          rule = authored(%{route | organization_id: org}, document),
          update = RoutingRuleStore.planned_change(Map.get(current, rule.routing_rule_id), rule),
          update != nil,
          do: update

    archives =
      rows
      |> active_rows()
      |> Enum.reject(&MapSet.member?(wanted, &1.routing_rule_id))
      |> Enum.map(&RoutingRuleStore.planned_archive/1)

    updates ++ archives
  end

  defp batch_spacecraft(context, proposed) do
    case Map.fetch(context.spacecraft, proposed["spacecraft_id"]) do
      {:ok, spacecraft} -> {:ok, spacecraft}
      :error -> unknown_spacecraft()
    end
  end

  defp active_rows(rows), do: Enum.reject(rows, &(&1.lifecycle_state == :archived))

  defp cannot_move do
    {:error,
     [
       F.error(
         "spacecraft_id",
         "An extra route can't move to another spacecraft; remove it and add one there"
       )
     ]}
  end

  defp unknown_spacecraft,
    do: {:error, [F.error("spacecraft_id", "That spacecraft doesn't exist")]}

  defp check_profile(spacecraft, routes, profile) do
    if Enum.any?(routes, &MapSet.member?(profile, route_choice(&1))),
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

  defp route_choice(rule),
    do: {rule.transport_id, Atom.to_string(rule.direction), Atom.to_string(rule.role)}

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
      do: cannot_move()

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

  def write(organization_id, mission_id, action, id, _previous, proposed, options) do
    with {:ok, spacecraft} <- spacecraft(organization_id, mission_id, proposed),
         {:ok, routes} <-
           plan(context(organization_id, mission_id), spacecraft, id, proposed),
         :ok <- replace_legacy(organization_id, spacecraft, action, routes, replaces(options)),
         :ok <-
           put_routes(
             organization_id,
             Enum.map(routes, &(&1 |> authored(proposed) |> converted(replaces(options))))
           ),
         wanted = MapSet.new(routes, & &1.routing_rule_id),
         :ok <-
           organization_id
           |> own_rows(mission_id, spacecraft.spacecraft_id, id)
           |> Enum.reject(&MapSet.member?(wanted, &1.routing_rule_id))
           |> archive(organization_id) do
      {:ok, document(own_rows(organization_id, mission_id, spacecraft.spacecraft_id, id)), []}
    end
  end

  @doc """
  Options: `"replaces"`, a create's legacy routing rule ids (the legacy route conversion, director
  11-16). Each must be an active legacy rule of THIS spacecraft, and together they must be exactly
  the route's legs: the same direction, role, transport, name and purpose, one rule per leg. The
  write archives them in the same apply transaction as it writes the route's rows, so a craft is
  never both legacy and converted, nor neither. An edit or a console create sets no options.
  """
  @impl true
  def normalize_options(:create, %{"replaces" => ids} = options)
      when map_size(options) == 1 and is_list(ids) and ids != [] do
    if Enum.all?(ids, &(is_binary(&1) and &1 != "")) and length(Enum.uniq(ids)) == length(ids),
      do: {:ok, options},
      else: {:error, [F.error("replaces", "Name each legacy routing rule once")]}
  end

  def normalize_options(_action, options) when options == %{}, do: {:ok, %{}}

  def normalize_options(_action, _options),
    do: {:error, [F.error("replaces", "Only a new extra route can replace legacy rules")]}

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
      {:error, _missing} -> unknown_spacecraft()
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
      |> MapSet.new(&route_choice/1)

    check_profile(spacecraft, routes, profile)
  end

  defp replaces(options), do: Map.get(options || %{}, "replaces", [])

  defp replace_legacy(_organization_id, _spacecraft, _action, _routes, []), do: :ok

  defp replace_legacy(organization_id, spacecraft, :create, routes, ids) do
    with {:ok, rules} <- legacy_rules(organization_id, spacecraft, ids),
         :ok <- same_legs(rules, routes) do
      archive(rules, organization_id)
    end
  end

  defp replace_legacy(_organization_id, _spacecraft, _action, _routes, _ids),
    do: {:error, [F.error("replaces", "Only a new extra route can replace legacy rules")]}

  defp legacy_rules(organization_id, spacecraft, ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case RoutingRuleStore.fetch_routing_rule(organization_id, spacecraft.mission_id, id) do
        {:ok, %{origin: :legacy, lifecycle_state: :active, spacecraft_id: sc} = rule}
        when sc == spacecraft.spacecraft_id ->
          {:cont, {:ok, [rule | acc]}}

        _other ->
          {:halt,
           {:error,
            [
              F.error(
                "replaces",
                "#{id} isn't an active legacy route of #{spacecraft.display_name}"
              )
            ]}}
      end
    end)
  end

  # Faithful or refused: the route's legs are exactly the replaced rules (the plan, the names and
  # the purposes an operator sees stay the same).
  defp same_legs(rules, routes) do
    if Enum.sort(Enum.map(rules, &leg_key/1)) == Enum.sort(Enum.map(routes, &leg_key/1)),
      do: :ok,
      else:
        {:error,
         [F.error("replaces", "The route's legs don't match the legacy routes it replaces")]}
  end

  defp leg_key(rule),
    do: {rule.direction, rule.role, rule.transport_id, rule.display_name, rule.purpose_label}

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

  # A route that replaced legacy rules says which (the conversion's progress counts these).
  defp converted(route, []), do: route

  defp converted(route, ids),
    do: %{route | metadata: Map.put(route.metadata, "converted_from", ids)}

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
