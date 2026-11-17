defmodule Cadence.Contacts.OverlappingContacts do
  @moduledoc """
  A mission's live (scheduled or realized) contacts whose window overlaps a time range, earliest
  first and bounded however large the plan: the `mission_runtime` item's next pass (U91).
  """

  import Ecto.Query

  alias Cadence.Contacts.ContactStore.ScheduledContactRow
  alias Cadence.Contacts.ScheduledContact
  alias Cadence.Repo

  @spec list(binary(), binary(), DateTime.t(), DateTime.t(), pos_integer()) ::
          [ScheduledContact.t()]
  def list(organization_id, mission_id, %DateTime{} = from, %DateTime{} = to, limit \\ 10) do
    ScheduledContactRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.lifecycle_state in ["scheduled", "realized"] and row.starts_at < ^to and
        (is_nil(row.ends_at) or row.ends_at > ^from)
    )
    |> order_by([row], asc: row.starts_at, asc: row.scheduled_contact_id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&ScheduledContactRow.to_domain/1)
  end
end
