defmodule Cadence.Contacts.OpenContacts do
  @moduledoc """
  A mission's open realized contacts (`defined` or `active`: a named release may still target
  them), for the console's uplink block (api U46): which contact a booked pass realized, and the
  live hand-started contacts (no scheduled contact).
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
end
