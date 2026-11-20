defmodule Cadence.Reads.PassListenerOverlap do
  @moduledoc """
  U58 (b), #361: the wire `listener_overlap` of booked passes, from `Contacts.ListenerOverlap`
  (the runtime's own listener rule).

  `null`, or `{with: {spacecraft: {id, name}, station: {code, name} | null, starts_at, state},
  seconds | nil, loses: "this" | "other" | "either", direction: "downlink" | "uplink", listener:
  {host, port}, count}` (`Contacts.ListenerOverlap` names the pass's own loss first):
  - `with` is always this mission's pass: ListenClaims keeps another mission off the endpoint.
    `spacecraft.id` and `name` are null only when the other pass's record doesn't say.
  - Cost (api-ops): listeners are resolved once per distinct route, the pairing is a sweep, and
    the named passes' facts come from the contacts already loaded, so the queries don't grow with
    the passes.
  - `listener` is for Technical details only (U58: no port in sentences).
  - `count` is how many passes it overlaps (1 when single).

  The mission's booked passes are read around the rows (12 h either side), scoped to the
  organization and mission, so a pass just outside the window, or hidden by a filter, still
  counts.
  """

  alias Cadence.Comms.StationRefs
  alias Cadence.Contacts.{ListenerOverlap, OverlappingContacts, ProviderReservations}
  alias Cadence.Reads.EventContacts
  alias Cadence.SpacecraftStore

  @margin_s 12 * 3600
  @max_contacts 2_000

  @doc "`%{scheduled_contact_id => listener_overlap | nil}` for rows `[%{starts_at, ends_at}]`."
  @spec for_rows(binary(), binary(), [map()]) :: %{binary() => map() | nil}
  def for_rows(_org, _mission, []), do: %{}

  def for_rows(org, mission, rows) do
    from = rows |> Enum.map(& &1.starts_at) |> Enum.min(DateTime) |> DateTime.add(-@margin_s)

    to =
      rows
      |> Enum.map(&(&1.ends_at || &1.starts_at))
      |> Enum.max(DateTime)
      |> DateTime.add(@margin_s)

    contacts = OverlappingContacts.list(org, mission, from, to, @max_contacts)
    flags = ListenerOverlap.for_scheduled(contacts)

    case flags |> Map.values() |> Enum.reject(&is_nil/1) do
      [] -> flags
      flagged -> name(flags, org, mission, contacts, flagged)
    end
  end

  defp name(flags, org, mission, contacts, flagged) do
    others = flagged |> Enum.map(& &1.with) |> MapSet.new()

    facts =
      EventContacts.facts_for(
        org,
        mission,
        Enum.filter(contacts, &(&1.scheduled_contact_id in others))
      )

    starts = Map.new(contacts, &{&1.scheduled_contact_id, &1.starts_at})

    crafts = craft_names(org, mission)

    Map.new(flags, fn
      {id, nil} -> {id, nil}
      {id, flag} -> {id, wire(flag, Map.get(facts, flag.with, %{}), starts, crafts)}
    end)
  end

  defp wire(flag, facts, starts, crafts) do
    spacecraft_id = Map.get(facts, :spacecraft_id)

    %{
      with: %{
        spacecraft: %{id: spacecraft_id, name: Map.get(crafts, spacecraft_id)},
        station: Map.get(facts, :station),
        starts_at: Map.get(starts, flag.with),
        state: "booked"
      },
      seconds: flag.seconds,
      loses: flag.loses,
      direction: Atom.to_string(flag.direction),
      listener: flag.listener,
      count: flag.count
    }
  end

  @doc """
  The plan's passes (`ContactOpportunitySnapshot`s): `%{snapshot_id => listener_overlap | nil}`,
  each against the plan's other passes (`with.state: "planned"`) and the mission's booked passes
  (`"booked"`). A plan's own bookings (reservations of its snapshots) are the pass itself, so
  they're left out. A planned pass's listeners come from its route's path template.
  """
  @spec for_plan(binary(), binary(), [map()], map()) :: %{binary() => map() | nil}
  def for_plan(_org, _mission, [], _stations), do: %{}

  def for_plan(org, mission, snapshots, stations) do
    from = snapshots |> Enum.map(& &1.starts_at) |> Enum.min(DateTime) |> DateTime.add(-@margin_s)

    to =
      snapshots
      |> Enum.map(&(&1.ends_at || &1.starts_at))
      |> Enum.max(DateTime)
      |> DateTime.add(@margin_s)

    templates =
      ListenerOverlap.template_listeners_by_ref(
        org,
        mission,
        Enum.map(snapshots, &template_ref/1)
      )

    planned = Enum.map(snapshots, &planned(&1, templates))
    rivals = booked_rivals(org, mission, from, to, snapshots)
    booked = booked_passes(rivals)
    flags = ListenerOverlap.overlaps(planned ++ booked)
    facts = named_facts(org, mission, flags, rivals)
    by_snapshot = Map.new(snapshots, &{&1.contact_opportunity_snapshot_id, &1})
    crafts = craft_names(org, mission)
    starts = Map.new(planned ++ booked, &{&1.id, &1.starts_at})

    Map.new(snapshots, fn snapshot ->
      id = snapshot.contact_opportunity_snapshot_id

      named =
        case flags[{:planned, id}] do
          nil -> nil
          flag -> plan_wire(flag, starts, facts, by_snapshot, stations, crafts)
        end

      {id, named}
    end)
  end

  defp template_ref(snapshot) do
    route = snapshot.route_binding_document || %{}
    {route["path_template_id"], route["path_template_version"]}
  end

  defp planned(snapshot, templates),
    do: %{
      id: {:planned, snapshot.contact_opportunity_snapshot_id},
      starts_at: snapshot.starts_at,
      ends_at: snapshot.ends_at,
      listeners: Map.get(templates, template_ref(snapshot), [])
    }

  # Booked passes, their listeners resolved once per distinct route.
  defp booked_passes(contacts) do
    listeners = ListenerOverlap.scheduled_listeners_by_id(contacts)

    Enum.map(
      contacts,
      &%{
        id: {:booked, &1.scheduled_contact_id},
        starts_at: &1.starts_at,
        ends_at: &1.ends_at,
        listeners: listeners[&1.scheduled_contact_id]
      }
    )
  end

  # The mission's booked passes in the window, less the ones booked from these snapshots.
  defp booked_rivals(org, mission, from, to, snapshots) do
    ids = MapSet.new(snapshots, & &1.contact_opportunity_snapshot_id)

    {reservations, _truncated} =
      ProviderReservations.list_in_window(org, mission, from, to, limit: @max_contacts)

    own = own_booking_ids(reservations, ids)

    org
    |> OverlappingContacts.list(mission, from, to, @max_contacts)
    |> Enum.reject(&MapSet.member?(own, &1.scheduled_contact_id))
  end

  # The facts (spacecraft, station) of the booked passes a flag names, from the contacts already
  # loaded: no lookup per contact (api-ops).
  defp named_facts(org, mission, flags, contacts) do
    named =
      for %{with: {:booked, id}} <- Map.values(flags), into: MapSet.new(), do: id

    EventContacts.facts_for(
      org,
      mission,
      Enum.filter(contacts, &(&1.scheduled_contact_id in named))
    )
  end

  @doc """
  The scheduled contacts booked FROM these snapshots (a reservation's
  `contact_opportunity_snapshot_id` in `snapshot_ids`): a plan's own bookings, which are its
  passes, never their rivals.
  """
  @spec own_booking_ids([map()], MapSet.t()) :: MapSet.t()
  def own_booking_ids(reservations, snapshot_ids) do
    for r <- reservations,
        r.contact_opportunity_snapshot_id in snapshot_ids,
        is_binary(r.scheduled_contact_id),
        into: MapSet.new(),
        do: r.scheduled_contact_id
  end

  defp plan_wire(flag, starts, facts, by_snapshot, stations, crafts) do
    {spacecraft_id, station, state} =
      case flag.with do
        {:booked, id} ->
          f = Map.get(facts, id, %{})
          {Map.get(f, :spacecraft_id), Map.get(f, :station), "booked"}

        {:planned, id} ->
          s = by_snapshot[id]
          station = StationRefs.of_snapshot(s, stations)

          {(s.route_binding_document || %{})["spacecraft_id"], Map.take(station, [:code, :name]),
           "planned"}
      end

    %{
      with: %{
        spacecraft: %{id: spacecraft_id, name: Map.get(crafts, spacecraft_id)},
        station: station,
        starts_at: starts[flag.with],
        state: state
      },
      seconds: flag.seconds,
      loses: flag.loses,
      direction: Atom.to_string(flag.direction),
      listener: flag.listener,
      count: flag.count
    }
  end

  @doc """
  Book a pass offers (`[{route, offer}]`, as `SingleBookings.Search` finds them): `%{offer_id =>
  listener_overlap | nil}`, each offer against the mission's booked passes. Offers are
  alternatives, so they're never checked against each other. An offer's listeners come from its
  route's path template. Booking is still allowed (U58 (b)).
  """
  @spec for_offers(binary(), binary(), [{map(), map()}]) :: %{term() => map() | nil}
  def for_offers(_org, _mission, []), do: %{}

  def for_offers(org, mission, found) do
    refs = Enum.map(found, fn {route, _offer} -> offer_ref(route) end)
    templates = ListenerOverlap.template_listeners_by_ref(org, mission, refs)

    # An offer without a readable start or end is left unflagged, never a crash (api-ops).
    {offers, untimed} =
      found
      |> Enum.map(&offer(&1, templates))
      |> Enum.split_with(&(match?(%DateTime{}, &1.starts_at) and match?(%DateTime{}, &1.ends_at)))

    for_timed(org, mission, offers)
    |> Map.merge(Map.new(untimed, fn %{id: {:offer, id}} -> {id, nil} end))
  end

  defp for_timed(_org, _mission, []), do: %{}

  defp for_timed(org, mission, offers) do
    from = offers |> Enum.map(& &1.starts_at) |> Enum.min(DateTime) |> DateTime.add(-@margin_s)

    to =
      offers
      |> Enum.map(&(&1.ends_at || &1.starts_at))
      |> Enum.max(DateTime)
      |> DateTime.add(@margin_s)

    contacts = OverlappingContacts.list(org, mission, from, to, @max_contacts)
    booked = booked_passes(contacts)

    flags = Map.new(offers, &{&1.id, ListenerOverlap.overlaps([&1 | booked])[&1.id]})
    facts = named_facts(org, mission, flags, contacts)
    crafts = craft_names(org, mission)
    starts = Map.new(booked, &{&1.id, &1.starts_at})

    Map.new(flags, fn
      {{:offer, id}, nil} -> {id, nil}
      {{:offer, id}, flag} -> {id, plan_wire(flag, starts, facts, %{}, %{}, crafts)}
    end)
  end

  defp offer_ref(route),
    do: {Map.get(route, :path_template_id), Map.get(route, :path_template_version)}

  defp offer({route, offer}, templates),
    do: %{
      id: {:offer, offer["id"]},
      starts_at: offer_at(offer["starts_at"]),
      ends_at: offer_at(offer["ends_at"]),
      listeners: Map.get(templates, offer_ref(route), [])
    }

  defp offer_at(%DateTime{} = at), do: at

  defp offer_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp offer_at(_value), do: nil

  defp craft_names(org, mission) do
    org
    |> SpacecraftStore.list_spacecraft(mission, include_archived: true)
    |> Map.new(&{&1.spacecraft_id, &1.display_name})
  end
end
