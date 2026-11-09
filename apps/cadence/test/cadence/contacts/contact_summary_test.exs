defmodule Cadence.Contacts.ContactSummaryTest do
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Control.Contacts
  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.ProviderChangeFixtures

  setup do
    c = ProviderChangeFixtures.setup_contact()
    Map.put(c, :sc, c.reservation.spacecraft_id)
  end

  test "a mission without reservations is not tracked" do
    other = ProviderChangeFixtures.setup_contact()

    Repo.delete_all(from(r in ProviderReservationRow, where: r.mission_id == ^other.mission_id))

    assert %{tracked?: false, passes_next_2h: nil, by_spacecraft: %{}} =
             Contacts.contact_summary(other.organization_id, other.mission_id, DateTime.utc_now())
  end

  test "before a confirmed pass: next AOS and a pass in the next 2 h", c do
    now = DateTime.add(c.reservation.starts_at, -3_600)
    summary = Contacts.contact_summary(c.organization_id, c.mission_id, now)

    assert summary.tracked?
    assert summary.passes_next_2h == 1

    assert summary.by_spacecraft[c.sc] == %{
             in_contact: false,
             next_aos_at: c.reservation.starts_at,
             last_los_at: nil
           }
  end

  test "after it: last LOS, nothing next", c do
    now = DateTime.add(c.reservation.ends_at, 3_600)
    summary = Contacts.contact_summary(c.organization_id, c.mission_id, now)

    assert summary.passes_next_2h == 0
    assert %{next_aos_at: nil, last_los_at: los, in_contact: false} = summary.by_spacecraft[c.sc]
    assert DateTime.compare(los, c.reservation.ends_at) == :eq
  end

  test "during an active pass: in contact; a canceled one never is", c do
    now = DateTime.add(c.reservation.starts_at, 60)
    set_state(c, "active")

    assert Contacts.contact_summary(c.organization_id, c.mission_id, now).by_spacecraft[c.sc].in_contact

    set_state(c, "canceled")
    summary = Contacts.contact_summary(c.organization_id, c.mission_id, now)
    refute Map.get(summary.by_spacecraft, c.sc, %{in_contact: false}).in_contact
  end

  defp set_state(c, state) do
    Repo.update_all(
      from(r in ProviderReservationRow,
        where: r.provider_reservation_id == ^c.reservation.provider_reservation_id
      ),
      set: [lifecycle_state: state]
    )
  end
end
