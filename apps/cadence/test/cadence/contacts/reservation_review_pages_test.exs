defmodule Cadence.Contacts.ReservationReviewPagesTest do
  use Cadence.DataCase, async: false
  alias Cadence.GroundNetworks.{ProviderAudit, ProviderAuditEntry}
  alias Cadence.ProviderChangeFixtures, as: Fixtures

  test "audit seeks within one reservation including equal timestamp ties and rejects foreign anchors" do
    c = Fixtures.setup_contact()
    r = c.reservation.provider_reservation_id

    for n <- 1..27 do
      assert {:ok, _} =
               ProviderAudit.append(
                 ProviderAuditEntry.new(%{
                   provider_audit_entry_id: "audit-#{String.pad_leading(to_string(n), 2, "0")}",
                   organization_id: c.organization_id,
                   mission_id: c.mission_id,
                   provider_reservation_id: r,
                   action: "test.review",
                   outcome: "recorded",
                   recorded_at: ~U[2027-01-01 00:00:00Z]
                 })
               )
    end

    assert {:ok, first} = ProviderAudit.list_reservation_page(c.organization_id, c.mission_id, r)
    assert length(first.entries) == 25
    assert first.next == "audit-03"

    assert {:ok, %{entries: rest, next: nil}} =
             ProviderAudit.list_reservation_page(c.organization_id, c.mission_id, r, first.next)

    assert Enum.map(rest, & &1.provider_audit_entry_id) == ["audit-02", "audit-01"]

    for {org, mission, reservation} <- [
          {"foreign", c.mission_id, r},
          {c.organization_id, "foreign", r},
          {c.organization_id, c.mission_id, "foreign"}
        ] do
      assert {:error, :invalid_reservation_audit_cursor} =
               ProviderAudit.list_reservation_page(org, mission, reservation, first.next)
    end
  end
end
