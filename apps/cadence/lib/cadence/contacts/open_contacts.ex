defmodule Cadence.Contacts.OpenContacts do
  @moduledoc """
  A mission's open realized contacts (`defined` or `active`: a named release may still target
  them), for the console's uplink block (api U46): which contact a booked pass realized, and the
  live hand-started contacts (no scheduled contact). `latest_for_scheduled/3` finds a booked
  pass's realized contact in any state (U50's second connections on the pass detail).
  """

  import Ecto.Query

  alias Cadence.Contacts.ContactStore.RealizedContactRow
  alias Cadence.Contacts.RealizedContact
  alias Cadence.Repo

  @open ~w(defined active)

  @spec list(binary(), binary()) :: [RealizedContact.t()]
  def list(org, mission) when is_binary(org) and is_binary(mission) do
    RealizedContactRow
    |> where(
      [row],
      row.organization_id == ^org and row.mission_id == ^mission and
        row.lifecycle_state in ^@open
    )
    |> Repo.all()
    |> Enum.map(&RealizedContactRow.to_domain/1)
  end

  @spec latest_for_scheduled(binary(), binary(), binary() | nil) :: RealizedContact.t() | nil
  def latest_for_scheduled(_org, _mission, nil), do: nil

  def latest_for_scheduled(org, mission, scheduled_contact_id) do
    RealizedContactRow
    |> where(
      [row],
      row.organization_id == ^org and row.mission_id == ^mission and
        row.scheduled_contact_id == ^scheduled_contact_id
    )
    |> order_by([row], desc_nulls_last: row.realized_at, desc: row.realized_contact_id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      row -> RealizedContactRow.to_domain(row)
    end
  end
end
