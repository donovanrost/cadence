defmodule Cadence.Contacts.ReservationActivity do
  @moduledoc """
  Which spacecraft have ever had provider reservations (spacecraft traffic, #49/#50), and which
  still have passes booked ahead (archiving one, L22).
  """

  import Ecto.Query

  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  # Still booked, or still being booked: what an operator would release in Contacts.
  @booked ~w(requesting pending confirmed unknown)

  @doc "The mission's reservations still booked ahead of `now` (the archive in-use check, U82)."
  @spec booked_ahead(binary(), binary(), DateTime.t()) :: [map()]
  def booked_ahead(organization_id, mission_id, %DateTime{} = now) do
    from(row in ProviderReservationRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.lifecycle_state in ^@booked and row.starts_at > ^now
    )
    |> Repo.all()
    |> Enum.map(&ProviderReservationRow.to_domain/1)
  end

  @spec spacecraft_with_reservations(binary(), binary(), [binary()]) :: MapSet.t()
  def spacecraft_with_reservations(_organization_id, _mission_id, []), do: MapSet.new()

  def spacecraft_with_reservations(organization_id, mission_id, spacecraft_ids) do
    ProviderReservationRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        r.spacecraft_id in ^spacecraft_ids
    )
    |> distinct(true)
    |> select([r], r.spacecraft_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Passes still booked to start after `now`: `%{spacecraft_id => %{count, earliest}}`."
  @spec upcoming(binary(), binary(), [binary()], DateTime.t()) :: %{binary() => map()}
  def upcoming(_organization_id, _mission_id, [], _now), do: %{}

  def upcoming(organization_id, mission_id, spacecraft_ids, now) do
    ProviderReservationRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        r.spacecraft_id in ^spacecraft_ids and r.lifecycle_state in ^@booked and
        r.starts_at > ^now
    )
    |> group_by([r], r.spacecraft_id)
    |> select(
      [r],
      {r.spacecraft_id, %{count: count(r.provider_reservation_id), earliest: min(r.starts_at)}}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Ids of the mission's off-plan bookings (L15, DECISIONS #78) made in `[from, to)` (either may be
  nil), newest first, at most `limit`. The booking row is written when it's booked.
  """
  @spec off_plan(binary(), binary(), DateTime.t() | nil, DateTime.t() | nil, pos_integer()) ::
          [binary()]
  def off_plan(organization_id, mission_id, from, to, limit) do
    ProviderReservationRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        fragment("(? -> 'value') \\? 'off_plan'", r.metadata)
    )
    |> then(&if(from, do: where(&1, [r], r.inserted_at >= ^from), else: &1))
    |> then(&if(to, do: where(&1, [r], r.inserted_at < ^to), else: &1))
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> select([r], r.provider_reservation_id)
    |> Repo.all()
  end
end
