defmodule Cadence.Reads.Passes do
  @moduledoc """
  Passes in a time window for the console (ops M7 = scheduling S1): one row per
  provider reservation whose window overlaps `[from, to)`, `booked: true`. With
  `hand_started: true` (U78 History), hand-started contacts join as `booked: false` rows
  (`Cadence.Reads.HandStartedPasses`).

  Station and antenna come from the reservation's newest snapshot (Cadence
  accepted, then provider confirmed, then requested). The station is matched to
  a Cadence ground station by id or code when possible. Cost and uplink are `nil`
  unless the provider supplied them; elevation is the provider's, else the matched
  predicted pass's (`Cadence.Reads.PassGeometry`, #892, one query per page).

  Provider opportunities (windows not yet booked) are not listed here; they
  need a live provider search per spacecraft.
  """

  alias Cadence.Comms.{GroundStationStore, StationRefs}
  alias Cadence.Contacts.{PassWindows, ProviderReservation, RealizedContact}
  alias Cadence.Control.Contacts
  alias Cadence.Reads.{HandStartedPasses, PassEnders, PassListenerOverlap, WindowCursor}
  alias Cadence.Reads.{PassGeometry, PassRow}

  @default_limit 500
  @hand_only_states ~w(defined stopped)

  @type filters :: %{
          optional(:spacecraft_id) => binary() | nil,
          optional(:spacecraft_ids) => [binary()] | nil,
          optional(:station) => binary() | nil,
          optional(:states) => [binary()] | nil,
          optional(:limit) => pos_integer(),
          optional(:order) => :asc | :desc,
          optional(:hand_started) => boolean(),
          optional(:overlap) => boolean(),
          optional(:cursor) => binary() | nil,
          optional(:after) => {DateTime.t(), binary(), integer()}
        }

  @doc "A page of passes and the counts over its entire filtered window."
  def page(org, mission, from, to, filters) do
    basis =
      {:passes, org, mission, DateTime.to_unix(from, :microsecond),
       DateTime.to_unix(to, :microsecond),
       Map.take(filters, [:spacecraft_id, :station, :states, :order, :hand_started])}

    with {:ok, after_key} <- WindowCursor.decode(Map.get(filters, :cursor), basis, [0, 1]) do
      filters = Map.put(filters, :after, after_key)
      station_refs = station_refs(org, mission, filters)
      filters = Map.put(filters, :station_refs, station_refs)
      result = load(org, mission, from, to, filters)

      cursor =
        if result.truncated do
          pass = List.last(result.passes)
          WindowCursor.encode(pass.starts_at, pass.id, kind(pass), basis)
        end

      {:ok,
       Map.merge(result, %{next_cursor: cursor, counts: counts(org, mission, from, to, filters)})}
    end
  end

  defp counts(org, mission, from, to, filters) do
    counts =
      case booked_states(Map.get(filters, :states)) do
        :none ->
          %{booked: 0, upcoming: 0, in_contact: 0, synthetic: 0}

        states ->
          PassWindows.reservation_counts(
            org,
            mission,
            from,
            to,
            reservation_opts(filters, states),
            DateTime.utc_now()
          )
      end

    hand_started =
      if filters[:hand_started],
        do: HandStartedPasses.count(org, mission, from, to, filters),
        else: 0

    Map.merge(counts, %{hand_started: hand_started, total: counts.booked + hand_started})
  end

  @doc """
  The passes in a window. Each carries its `listener_overlap`, which resolves the paths of every
  booked contact around the window; `overlap: false` skips that (rows carry `listener_overlap:
  nil`) for a caller that only needs windows, stations and refs (#1051). Default `true`.
  """
  @spec load(binary(), binary(), DateTime.t(), DateTime.t(), filters()) :: map()
  def load(organization_id, mission_id, from, to, filters \\ %{}) do
    limit = Map.get(filters, :limit, @default_limit)
    order = Map.get(filters, :order, :asc)

    filters =
      Map.put_new_lazy(filters, :station_refs, fn ->
        station_refs(organization_id, mission_id, filters)
      end)

    {reservations, truncated?} =
      case booked_states(Map.get(filters, :states)) do
        :none ->
          {[], false}

        states ->
          PassWindows.reservations(
            organization_id,
            mission_id,
            from,
            to,
            reservation_opts(filters, states)
          )
      end

    organization_id
    |> load_rows(mission_id, reservations, %{
      from: from,
      to: to,
      truncated: truncated?,
      overlap?: Map.get(filters, :overlap, true)
    })
    |> with_hand_started(organization_id, mission_id, filters, limit, order)
    |> Map.update!(:passes, &PassGeometry.contacts(organization_id, mission_id, &1))
  end

  @default_pages 40

  @doc """
  Every pass matching `filters` in the window, paging by the keyset until the read is complete
  (E2/#1040: a decision such as "this target has no contact" is never made from a truncated read).
  `{:ok, passes}`, or `{:error, :truncated}` if `max_pages` pages (default #{@default_pages} of the
  filters' `limit`, 500 by default) still aren't the whole answer. Filter by `spacecraft_ids` to
  read only a group's targets. `overlap: false` leaves out the listener-overlap decoration (`load/5`
  says why a caller would).
  """
  @spec load_all(binary(), binary(), DateTime.t(), DateTime.t(), filters(), pos_integer()) ::
          {:ok, [map()]} | {:error, :truncated}
  def load_all(org, mission, from, to, filters \\ %{}, max_pages \\ @default_pages),
    do: collect(org, mission, from, to, filters, max_pages, [])

  defp collect(_org, _mission, _from, _to, _filters, 0, _acc), do: {:error, :truncated}

  defp collect(org, mission, from, to, filters, pages, acc) do
    result = load(org, mission, from, to, filters)
    acc = Enum.reverse(result.passes, acc)

    if result.truncated do
      last = List.last(result.passes)
      after_key = {last.starts_at, last.id, kind(last)}
      collect(org, mission, from, to, Map.put(filters, :after, after_key), pages - 1, acc)
    else
      {:ok, Enum.reverse(acc)}
    end
  end

  # U78: hand-started contacts join only on request (`include=hand_started`), merged in the same
  # order and cut to the same limit, so the kept rows are the first `limit` of the whole list.
  defp with_hand_started(result, org, mission, %{hand_started: true} = filters, limit, order) do
    {rows, truncated?} = HandStartedPasses.load(org, mission, result.from, result.to, filters)
    merged = merge(result.passes, rows, order)

    %{
      result
      | passes: Enum.take(merged, limit),
        truncated: result.truncated or truncated? or length(merged) > limit
    }
  end

  defp with_hand_started(result, _org, _mission, _filters, _limit, _order), do: result

  defp merge(booked, [], _order), do: booked

  defp merge(booked, hand, order) do
    key = &{DateTime.to_unix(&1.starts_at, :microsecond), &1.id, kind(&1)}
    Enum.sort_by(booked ++ hand, key, order)
  end

  defp kind(%{booked: true}), do: 0
  defp kind(_hand_started), do: 1

  defp station_refs(_org, _mission, %{station: nil}), do: nil

  defp station_refs(org, mission, %{station: station}),
    do: StationRefs.matching_refs(StationRefs.index(org, mission), station)

  defp station_refs(_org, _mission, _filters), do: nil

  defp reservation_opts(filters, states) do
    [
      spacecraft_id: Map.get(filters, :spacecraft_id),
      spacecraft_ids: Map.get(filters, :spacecraft_ids),
      station_refs: Map.get(filters, :station_refs),
      states: states,
      after: Map.get(filters, :after),
      order: Map.get(filters, :order, :asc),
      limit: Map.get(filters, :limit, @default_limit)
    ]
  end

  # A states filter applies to bookings in SQL (before the cut); words only a hand-started
  # contact carries (defined, stopped) match no booking.
  defp booked_states(nil), do: nil

  defp booked_states(states) do
    case Enum.reject(states, &(&1 in @hand_only_states)) do
      [] -> :none
      booked -> booked
    end
  end

  @doc """
  One pass by its reservation id, in the same row shape (U32: Review opens any pass). Writes and
  their re-reads use this: a contact id is no pass to act on.
  """
  @spec fetch(binary(), binary(), binary()) :: {:ok, map()} | {:error, :pass_not_found}
  def fetch(organization_id, mission_id, reservation_id) do
    case Contacts.fetch_provider_reservation(organization_id, mission_id, reservation_id) do
      {:ok, %ProviderReservation{} = reservation} ->
        {:ok, one(organization_id, mission_id, reservation)}

      {:error, _reason} ->
        {:error, :pass_not_found}
    end
  end

  @doc """
  `GET /passes/:id` (U78): `fetch/3`, or a scheduled contact id (the reservation that booked it)
  or a realized contact id (the pass of the contact it realized, else, started by hand, its
  `booked: false` row). Reservation ids are tried first, so today's lookups never change, and a
  scheduled id never gives a hand-started row. Scoped to the mission like `fetch/3`.
  """
  @spec resolve(binary(), binary(), binary()) :: {:ok, map()} | {:error, :pass_not_found}
  def resolve(organization_id, mission_id, id) do
    with {:error, :pass_not_found} <- fetch(organization_id, mission_id, id),
         {:error, _not_scheduled} <- by_scheduled(organization_id, mission_id, id) do
      by_realized(organization_id, mission_id, id)
    else
      {:ok, %ProviderReservation{} = reservation} ->
        {:ok, one(organization_id, mission_id, reservation)}

      {:ok, pass} ->
        {:ok, pass}
    end
  end

  defp by_scheduled(org, mission, id) do
    case Contacts.fetch_scheduled_contact(org, mission, id) do
      {:ok, _scheduled} -> booking(org, mission, id)
      {:error, _reason} -> {:error, :not_scheduled}
    end
  end

  defp by_realized(org, mission, id) do
    case Contacts.fetch_realized_contact(org, mission, id) do
      {:ok, %RealizedContact{scheduled_contact_id: nil} = contact} ->
        {:ok, geometry(org, mission, HandStartedPasses.row(org, mission, contact))}

      {:ok, %RealizedContact{scheduled_contact_id: scheduled_id}} ->
        case booking(org, mission, scheduled_id) do
          {:ok, %ProviderReservation{} = reservation} -> {:ok, one(org, mission, reservation)}
          {:error, :pass_not_found} -> {:error, :pass_not_found}
        end

      {:error, _reason} ->
        {:error, :pass_not_found}
    end
  end

  # A scheduled contact with no booking (made through the control-plane API) has no pass row.
  defp booking(org, mission, scheduled_id) do
    case PassWindows.reservation_for_scheduled(org, mission, scheduled_id) do
      {:ok, reservation} -> {:ok, reservation}
      {:error, _reason} -> {:error, :pass_not_found}
    end
  end

  defp one(org, mission, %ProviderReservation{} = reservation) do
    %{passes: [pass]} =
      load_rows(org, mission, [reservation], %{from: nil, to: nil, truncated: false, filters: %{}})

    geometry(org, mission, pass)
  end

  defp geometry(org, mission, row), do: hd(PassGeometry.contacts(org, mission, [row]))

  defp load_rows(organization_id, mission_id, reservations, window) do
    {overlap?, window} = Map.pop(window, :overlap?, true)
    ids = for r <- reservations, is_binary(r.spacecraft_id), do: r.spacecraft_id

    {:ok, spacecraft} =
      Cadence.SpacecraftStore.fetch_spacecrafts_in_batches(organization_id, mission_id, ids)

    window
    |> Map.merge(%{
      filters: %{},
      reservations: reservations,
      enders: PassEnders.load(organization_id, mission_id, reservations),
      stations: GroundStationStore.list_ground_stations(organization_id, mission_id),
      spacecraft: Map.values(spacecraft),
      # U58 (b), #361: a booked pass that loses its start to a one-connection listener. Reading it
      # resolves the paths of every booked contact around the window, so a caller that only needs
      # windows and refs (`overlap: false`, #1051) skips it and its rows carry `listener_overlap: nil`.
      overlaps: overlaps(overlap?, organization_id, mission_id, reservations)
    })
    |> build()
  end

  defp overlaps(false, _organization_id, _mission_id, _reservations), do: %{}

  defp overlaps(true, organization_id, mission_id, reservations),
    do: PassListenerOverlap.for_rows(organization_id, mission_id, reservations)

  @doc "Pure builder; see `load/5`."
  @spec build(map()) :: map()
  def build(%{reservations: reservations, stations: stations, filters: filters} = input) do
    index = StationRefs.build(stations)
    crafts = Map.new(Map.get(input, :spacecraft, []), &{&1.spacecraft_id, &1})
    states = filters |> Map.get(:states) |> List.wrap() |> MapSet.new()
    station = Map.get(filters, :station)

    enders = Map.get(input, :enders, %{})
    overlaps = Map.get(input, :overlaps, %{})

    passes =
      reservations
      |> Enum.map(
        &(&1
          |> PassRow.row(index, crafts)
          |> Map.put(:ended_by, PassEnders.ended_by(&1, enders))
          |> Map.put(:listener_overlap, Map.get(overlaps, &1.scheduled_contact_id)))
      )
      |> Enum.filter(&(state_match?(&1, states) and station_match?(&1, station)))

    %{from: input.from, to: input.to, truncated: input.truncated, passes: passes}
  end

  defp state_match?(pass, states), do: MapSet.size(states) == 0 or pass.state in states

  defp station_match?(_pass, nil), do: true

  defp station_match?(pass, station),
    do: station in [pass.station.ref, pass.station.id, pass.station.code]
end
