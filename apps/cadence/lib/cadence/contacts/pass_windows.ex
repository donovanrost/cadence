defmodule Cadence.Contacts.PassWindows do
  @moduledoc """
  The window queries behind the console's passes read (ops M7, U78 History):

    * `reservations/5`: provider reservations whose window overlaps `[from, to)`;
    * `hand_started/5`: realized contacts with no scheduled contact (started by hand, #84) whose
      time overlaps `[from, to)`;
    * `reservation_for_scheduled/3`: the reservation that booked a scheduled contact.

  Both window queries take `:order` (`:asc`, the default, or `:desc` by start), `:limit` (default
  500), `:states` (lifecycle words; nil for any), `:station_refs`, and an optional `:after`
  key. They return `{entries, more?}` in that order.
  """

  import Ecto.Query

  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Contacts.{ProviderReservation, RealizedContact}
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  @default_limit 500
  @open ~w(defined active)
  @upcoming ~w(confirmed active)
  @dead ~w(rejected canceling canceled failed)

  @spec reservations(binary(), binary(), DateTime.t(), DateTime.t(), keyword()) ::
          {[ProviderReservation.t()], boolean()}
  def reservations(org, mission, %DateTime{} = from, %DateTime{} = to, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    org
    |> reservation_window(mission, from, to, opts)
    |> seek(opts, 0, dynamic([r], r.starts_at), dynamic([r], r.provider_reservation_id))
    |> order_by([r], [
      {^direction(opts), r.starts_at},
      {^direction(opts), fragment("? COLLATE \"C\"", r.provider_reservation_id)}
    ])
    |> limit(^(limit + 1))
    |> Repo.all()
    |> page(limit, &ProviderReservationRow.to_domain/1)
  end

  @doc "Counts matching bookings over the whole window, independently of the page."
  def reservation_counts(org, mission, from, to, opts, now) do
    snapshot = reservation_snapshot()

    counts = %{
      booked: dynamic([], count()),
      in_contact:
        dynamic(
          [r],
          filter(
            count(r.spacecraft_id, :distinct),
            r.starts_at <= ^now and r.ends_at > ^now and
              (r.lifecycle_state == "active" or r.pass_phase == "pass") and
              r.lifecycle_state not in ^@dead
          )
        ),
      upcoming:
        dynamic([r], filter(count(), r.starts_at > ^now and r.lifecycle_state in ^@upcoming)),
      synthetic:
        dynamic(
          [],
          filter(
            count(),
            fragment(
              "COALESCE(?->'synthetic', ?->'extensions'->'synthetic') = 'true'::jsonb",
              ^snapshot,
              ^snapshot
            )
          )
        )
    }

    org
    |> reservation_window(mission, from, to, opts)
    |> select(^counts)
    |> Repo.one!()
  end

  defp reservation_window(org, mission, from, to, opts) do
    ProviderReservationRow
    |> where([r], r.organization_id == ^org and r.mission_id == ^mission)
    |> where([r], r.starts_at < ^to and r.ends_at > ^from)
    |> spacecraft(Keyword.get(opts, :spacecraft_id))
    |> states(Keyword.get(opts, :states))
    |> station(Keyword.get(opts, :station_refs), reservation_station_ref())
  end

  defp reservation_snapshot do
    accepted = nonempty_object(dynamic([r], r.cadence_accepted_snapshot_document))
    confirmed = nonempty_object(dynamic([r], r.provider_confirmed_snapshot_document))
    requested = nonempty_object(dynamic([r], r.requested_snapshot_document))
    dynamic([], fragment("COALESCE(?, ?, ?)", ^accepted, ^confirmed, ^requested))
  end

  defp nonempty_object(document) do
    object = unwrapped(document)

    dynamic(
      [],
      fragment(
        "CASE WHEN jsonb_typeof(?) = 'object' THEN NULLIF(?, '{}'::jsonb) END",
        ^object,
        ^object
      )
    )
  end

  defp unwrapped(document),
    do: dynamic([], fragment("COALESCE(?->'value', ?)", ^document, ^document))

  defp text(document, key) do
    dynamic(
      [],
      fragment(
        "CASE WHEN jsonb_typeof(?->?) = 'string' THEN NULLIF(?->>?, '') END",
        ^document,
        type(^key, :string),
        ^document,
        type(^key, :string)
      )
    )
  end

  defp reservation_text(key) do
    snapshot_value = text(reservation_snapshot(), key)
    metadata_value = text(unwrapped(dynamic([r], r.metadata)), key)
    dynamic([], coalesce(^snapshot_value, ^metadata_value))
  end

  defp reservation_station_ref, do: reservation_text("ground_station_ref")

  @doc "Compact ordered facts for the findings query, without row decoration."
  def finding_bookings(org, mission, from, to) do
    station_ref = reservation_station_ref()
    antenna_ref = reservation_text("antenna_or_service_pool_ref")

    fields = %{
      id: dynamic([r], selected_as(r.provider_reservation_id, :id)),
      spacecraft_id: dynamic([r], selected_as(r.spacecraft_id, :spacecraft_id)),
      starts_at: dynamic([r], selected_as(r.starts_at, :starts_at)),
      ends_at: dynamic([r], selected_as(r.ends_at, :ends_at)),
      state: dynamic([r], selected_as(r.lifecycle_state, :state)),
      station_ref: dynamic([], selected_as(^station_ref, :station_ref)),
      antenna_ref: dynamic([], selected_as(^antenna_ref, :antenna_ref))
    }

    org
    |> reservation_window(mission, from, to, states: ~w(requesting pending confirmed active))
    |> select(^fields)
  end

  @doc "Station impact counts for the whole window and a bounded list of booking references."
  def station_impact(org, mission, station_id, from, to, live_states, lost_states, limit) do
    station = impact_station_ref()

    query =
      org
      |> reservation_window(mission, from, to, states: live_states ++ lost_states)
      |> where(^dynamic([], ^station == type(^station_id, :string)))

    counts =
      query
      |> select([r], %{
        spacecraft_count: count(r.spacecraft_id, :distinct),
        hit: filter(count(), r.lifecycle_state in ^live_states),
        lost: filter(count(), r.lifecycle_state in ^lost_states)
      })
      |> Repo.one!()

    rows =
      query
      |> order_by([r], asc: r.starts_at, asc: r.provider_reservation_id)
      |> select([r], %{
        provider_reservation_id: r.provider_reservation_id,
        spacecraft_id: r.spacecraft_id,
        contact_plan_id: r.contact_plan_id,
        contact_plan_version: r.contact_plan_version,
        lifecycle_state: r.lifecycle_state
      })
      |> limit(^(limit + 1))
      |> Repo.all()

    {counts, Enum.take(rows, limit), length(rows) > limit}
  end

  # Station impact uses the provider's last word, falling back to the request and metadata.
  defp impact_station_ref do
    dynamic(
      [r],
      fragment(
        "COALESCE(COALESCE(?->'value', ?)->>'ground_station_ref', COALESCE(?->'value', ?)->>'ground_station_ref', COALESCE(?->'value', ?)->>'ground_station_ref')",
        r.provider_confirmed_snapshot_document,
        r.provider_confirmed_snapshot_document,
        r.requested_snapshot_document,
        r.requested_snapshot_document,
        r.metadata,
        r.metadata
      )
    )
  end

  @doc """
  Hand-started contacts overlapping `[from, to)`, ordered by when they went live. A contact
  is open until its stop, completion or never-started close (metadata `stopped_at`,
  `completed_at`, `not_started.at`); a closed one without any of those ends when it was realized.
  Option `:endpoint_refs` narrows to contacts on any of those source endpoints (a spacecraft's).
  """
  @spec hand_started(binary(), binary(), DateTime.t(), DateTime.t(), keyword()) ::
          {[RealizedContact.t()], boolean()}
  def hand_started(org, mission, %DateTime{} = from, %DateTime{} = to, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    starts_at = hand_start()
    dir = direction(opts)
    id = dynamic([c], fragment("? COLLATE \"C\"", c.realized_contact_id))

    sort = [{dir, starts_at}, {dir, id}]

    org
    |> hand_window(mission, from, to, opts)
    |> seek(opts, 1, starts_at, dynamic([c], c.realized_contact_id))
    |> order_by(^sort)
    |> limit(^(limit + 1))
    |> Repo.all()
    |> page(limit, &RealizedContactRow.to_domain/1)
  end

  @doc "Counts matching hand-started contacts over the whole window."
  def hand_count(org, mission, from, to, opts) do
    org |> hand_window(mission, from, to, opts) |> Repo.aggregate(:count)
  end

  defp hand_window(org, mission, from, to, opts) do
    starts_at = hand_start()
    before_to = dynamic([], ^starts_at < type(^to, :utc_datetime_usec))

    station_ref = text(unwrapped(dynamic([c], c.metadata)), "ground_station_ref")

    RealizedContactRow
    |> where([c], c.organization_id == ^org and c.mission_id == ^mission)
    |> where([c], is_nil(c.scheduled_contact_id) and c.realized_at < ^to)
    |> where(^before_to)
    |> where(
      [c],
      fragment(
        "coalesce(COALESCE(?->'value', ?)->>'stopped_at', COALESCE(?->'value', ?)->>'completed_at', COALESCE(?->'value', ?)->'not_started'->>'at')::timestamptz AT TIME ZONE 'UTC'",
        c.metadata,
        c.metadata,
        c.metadata,
        c.metadata,
        c.metadata,
        c.metadata
      ) > ^from or
        (is_nil(
           fragment(
             "coalesce(COALESCE(?->'value', ?)->>'stopped_at', COALESCE(?->'value', ?)->>'completed_at', COALESCE(?->'value', ?)->'not_started'->>'at')",
             c.metadata,
             c.metadata,
             c.metadata,
             c.metadata,
             c.metadata,
             c.metadata
           )
         ) and (c.lifecycle_state in ^@open or c.realized_at >= ^from))
    )
    |> endpoints(Keyword.get(opts, :endpoint_refs))
    |> states(Keyword.get(opts, :states))
    |> station(Keyword.get(opts, :station_refs), station_ref)
  end

  defp hand_start do
    dynamic(
      [c],
      fragment(
        "COALESCE((COALESCE(?->'value', ?)->'start_failure'->>'started_at')::timestamptz AT TIME ZONE 'UTC', ?)",
        c.metadata,
        c.metadata,
        c.realized_at
      )
    )
  end

  @doc "The newest reservation that booked this scheduled contact."
  @spec reservation_for_scheduled(binary(), binary(), binary()) ::
          {:ok, ProviderReservation.t()} | {:error, :provider_reservation_not_found}
  def reservation_for_scheduled(org, mission, scheduled_contact_id)
      when is_binary(org) and is_binary(mission) and is_binary(scheduled_contact_id) do
    ProviderReservationRow
    |> where(
      [r],
      r.organization_id == ^org and r.mission_id == ^mission and
        r.scheduled_contact_id == ^scheduled_contact_id
    )
    |> order_by([r], desc: r.inserted_at, desc: r.provider_reservation_id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:error, :provider_reservation_not_found}
      row -> {:ok, ProviderReservationRow.to_domain(row)}
    end
  end

  defp page(rows, limit, to_domain),
    do: {rows |> Enum.take(limit) |> Enum.map(to_domain), length(rows) > limit}

  defp direction(opts), do: if(Keyword.get(opts, :order) == :desc, do: :desc, else: :asc)

  defp spacecraft(query, nil), do: query
  defp spacecraft(query, id), do: where(query, [r], r.spacecraft_id == ^id)

  defp states(query, nil), do: query
  defp states(query, states), do: where(query, [r], r.lifecycle_state in ^states)

  defp station(query, nil, _station_ref), do: query
  defp station(query, refs, station_ref), do: where(query, ^dynamic([], ^station_ref in ^refs))

  defp seek(query, opts, kind, starts_at, id) do
    case Keyword.get(opts, :after) do
      nil ->
        query

      {at, cursor_id, cursor_kind} ->
        row = dynamic([], fragment("ROW(?, ? COLLATE \"C\")", ^starts_at, ^id))

        cursor =
          dynamic(
            [],
            fragment("ROW(?, ?)", type(^at, :utc_datetime_usec), type(^cursor_id, :string))
          )

        condition =
          case direction(opts) do
            :asc when kind > cursor_kind -> dynamic([], ^row >= ^cursor)
            :asc -> dynamic([], ^row > ^cursor)
            :desc when kind < cursor_kind -> dynamic([], ^row <= ^cursor)
            :desc -> dynamic([], ^row < ^cursor)
          end

        where(query, ^condition)
    end
  end

  defp endpoints(query, nil), do: query

  defp endpoints(query, refs),
    do: where(query, [c], fragment("? && ?", c.source_endpoint_refs, ^refs))
end
