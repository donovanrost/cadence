defmodule Cadence.Contacts.ReservationActivity do
  @moduledoc "Which spacecraft have ever had provider reservations (spacecraft traffic, #49/#50)."

  import Ecto.Query

  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.Repo

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
end
