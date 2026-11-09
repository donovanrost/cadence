defmodule Cadence.Contacts.SingleBookings do
  @moduledoc """
  Live bookings made outside any plan (a single booking through `actions/reserve`). A repair
  pairs them with the lost bookings they cover (DECISIONS #56), so it doesn't book that need a
  second time.
  """

  import Ecto.Query

  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

  @live ~w(requesting pending confirmed active unknown)

  @doc "`[%{provider_reservation_id, spacecraft_id, starts_at}]` overlapping `[from, to)`."
  @spec live(binary(), binary(), DateTime.t(), DateTime.t()) :: [map()]
  def live(organization_id, mission_id, %DateTime{} = from, %DateTime{} = to) do
    ProviderReservationRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        is_nil(r.contact_plan_id) and r.lifecycle_state in ^@live and
        r.starts_at < ^to and r.ends_at > ^from
    )
    |> order_by([r], asc: r.starts_at, asc: r.provider_reservation_id)
    |> select([r], %{
      provider_reservation_id: r.provider_reservation_id,
      spacecraft_id: r.spacecraft_id,
      starts_at: r.starts_at
    })
    |> Repo.all()
  end

  def live(_organization_id, _mission_id, _from, _to), do: []
end
