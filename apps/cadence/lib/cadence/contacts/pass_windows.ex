defmodule Cadence.Contacts.PassWindows do
  @moduledoc """
  The window queries behind the console's passes read (ops M7, U78 History):

    * `reservations/5`: provider reservations whose window overlaps `[from, to)`;
    * `hand_started/5`: realized contacts with no scheduled contact (started by hand, #84) whose
      time overlaps `[from, to)`;
    * `reservation_for_scheduled/3`: the reservation that booked a scheduled contact.

  Both window queries take `:order` (`:asc`, the default, or `:desc` by start), `:limit` (default
  500) and `:states` (lifecycle words; nil for any), and return `{entries, truncated?}` in that
  order, so a truncated page keeps the first `limit` of it.
  """

  import Ecto.Query

  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Contacts.{ProviderReservation, RealizedContact}
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  @default_limit 500
  @open ~w(defined active)

  @spec reservations(binary(), binary(), DateTime.t(), DateTime.t(), keyword()) ::
          {[ProviderReservation.t()], boolean()}
  def reservations(org, mission, %DateTime{} = from, %DateTime{} = to, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    ProviderReservationRow
    |> where([r], r.organization_id == ^org and r.mission_id == ^mission)
    |> where([r], r.starts_at < ^to and r.ends_at > ^from)
    |> spacecraft(Keyword.get(opts, :spacecraft_id))
    |> states(Keyword.get(opts, :states))
    |> order_by([r], [
      {^direction(opts), r.starts_at},
      {^direction(opts), r.provider_reservation_id}
    ])
    |> limit(^(limit + 1))
    |> Repo.all()
    |> page(limit, &ProviderReservationRow.to_domain/1)
  end

  @doc """
  Hand-started contacts overlapping `[from, to)`, ordered by when they were realized. A contact
  is open until its stop, completion or never-started close (metadata `stopped_at`,
  `completed_at`, `not_started.at`); a closed one without any of those ends when it was realized.
  Option `:endpoint_refs` narrows to contacts on any of those source endpoints (a spacecraft's).
  """
  @spec hand_started(binary(), binary(), DateTime.t(), DateTime.t(), keyword()) ::
          {[RealizedContact.t()], boolean()}
  def hand_started(org, mission, %DateTime{} = from, %DateTime{} = to, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    RealizedContactRow
    |> where([c], c.organization_id == ^org and c.mission_id == ^mission)
    |> where([c], is_nil(c.scheduled_contact_id) and c.realized_at < ^to)
    |> where(
      [c],
      fragment(
        "coalesce((?->>'stopped_at')::timestamptz, (?->>'completed_at')::timestamptz, (?->'not_started'->>'at')::timestamptz)",
        c.metadata,
        c.metadata,
        c.metadata
      ) > ^from or
        (is_nil(
           fragment(
             "coalesce(?->>'stopped_at', ?->>'completed_at', ?->'not_started'->>'at')",
             c.metadata,
             c.metadata,
             c.metadata
           )
         ) and (c.lifecycle_state in ^@open or c.realized_at >= ^from))
    )
    |> endpoints(Keyword.get(opts, :endpoint_refs))
    |> states(Keyword.get(opts, :states))
    |> order_by([c], [
      {^direction(opts), c.realized_at},
      {^direction(opts), c.realized_contact_id}
    ])
    |> limit(^(limit + 1))
    |> Repo.all()
    |> page(limit, &RealizedContactRow.to_domain/1)
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

  defp endpoints(query, nil), do: query

  defp endpoints(query, refs),
    do: where(query, [c], fragment("? && ?", c.source_endpoint_refs, ^refs))
end
