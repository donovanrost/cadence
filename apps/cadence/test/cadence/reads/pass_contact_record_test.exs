defmodule Cadence.Reads.PassContactRecordTest do
  @moduledoc "L14 / A13: a pass's contact record, from either side of the pair."
  use Cadence.ConfigCase, async: false

  alias Cadence.Control.Contacts
  alias Cadence.ProviderChangeFixtures, as: Fixtures
  alias Cadence.Reads.PassContactRecord

  test "a scheduled contact: its window, paths and schedule history, newest first" do
    c = Fixtures.setup_contact()

    assert {:ok, _} =
             Fixtures.advance(c, 2, %{
               "starts_at" => Fixtures.shift(c.baseline["starts_at"], 60),
               "ends_at" => Fixtures.shift(c.baseline["ends_at"], 60)
             })

    {:ok, reservation} =
      Contacts.fetch_provider_reservation(
        c.organization_id,
        c.mission_id,
        c.reservation.provider_reservation_id
      )

    id = reservation.scheduled_contact_id
    assert is_binary(id)

    assert {:ok, record} = PassContactRecord.load(c.organization_id, c.mission_id, id)

    assert %{subject: %{id: ^id, kind: "scheduled"}, scheduled: %{id: ^id}, truncated: false} =
             record

    assert [%{revision: newest} | _] = record.revisions.entries
    assert newest == record.scheduled.current_revision
    revisions = Enum.map(record.revisions.entries, & &1.revision)
    assert revisions == Enum.sort(revisions, :desc)
    assert Enum.all?(record.revisions.entries, &Map.has_key?(&1, :starts_at))

    assert Enum.all?(record.paths, &(&1.side == "scheduled" and is_list(&1.provider_bindings)))

    assert {:error, :invalid_cursor} =
             PassContactRecord.load(c.organization_id, c.mission_id, id, "nope")

    assert {:error, :contact_not_found} =
             PassContactRecord.load(c.organization_id, c.mission_id, "nope")
  end

  test "a hand-started realized contact: its clock and paths with their bindings" do
    import Cadence.GroupReleaseFixtures

    persist_mission_scope(org(), mission())
    alpha = persist_target!("alpha", 0)
    contact = uplink_contact!(alpha)
    id = contact.realized_contact_id

    assert {:ok, record} = PassContactRecord.load(org(), mission(), id)
    assert %{subject: %{kind: "realized"}, scheduled: nil, realized: %{id: ^id}} = record
    assert %{revisions: %{entries: [], next_cursor: nil}} = record

    assert [%{side: "realized", direction: "uplink", transport_bindings: [binding]}] =
             record.paths

    assert %{family_key: "uplink_gateway", target_scope: "path"} = binding
  end
end
