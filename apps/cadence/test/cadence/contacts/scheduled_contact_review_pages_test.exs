defmodule Cadence.Contacts.ScheduledContactReviewPagesTest do
  use Cadence.DataCase, async: false
  alias Cadence.Contacts.{ScheduledContactRevision, ScheduledContactRevisions}
  alias Cadence.Control.Contacts.Store.ScheduledContactRevisionRow
  alias Cadence.ProviderChangeFixtures, as: Fixtures

  test "scoped immutable history seeks behind the reviewed revision without page drift" do
    c = Fixtures.setup_contact()
    id = c.reservation.scheduled_contact_id

    for revision <- 2..29 do
      assert {:ok, _} =
               Repo.insert(
                 ScheduledContactRevisionRow.changeset(
                   ScheduledContactRevision.new(%{
                     organization_id: c.organization_id,
                     mission_id: c.mission_id,
                     scheduled_contact_id: id,
                     revision: revision,
                     created_by: "review-fixture",
                     snapshot_document: %{"starts_at" => c.baseline["starts_at"]}
                   })
                 )
               )
    end

    assert {:ok, page} =
             ScheduledContactRevisions.list_page(c.organization_id, c.mission_id, id, 28)

    assert Enum.map(page.entries, & &1.revision) == Enum.to_list(28..4//-1)
    assert page.next == 4

    assert {:ok, %{entries: rest, next: nil}} =
             ScheduledContactRevisions.list_page(
               c.organization_id,
               c.mission_id,
               id,
               28,
               page.next
             )

    assert Enum.map(rest, & &1.revision) == [3, 2, 1]

    for {org, mission} <- [{"foreign", c.mission_id}, {c.organization_id, "foreign"}] do
      assert {:ok, %{entries: []}} = ScheduledContactRevisions.list_page(org, mission, id, 28)

      assert {:error, :scheduled_contact_revision_not_found} =
               ScheduledContactRevisions.fetch_scoped(org, mission, id, 1)
    end

    for cursor <- [0, -1, "4", 1.5, 2_147_483_648] do
      assert {:error, :invalid_contact_revision_cursor} =
               ScheduledContactRevisions.list_page(
                 c.organization_id,
                 c.mission_id,
                 id,
                 28,
                 cursor
               )
    end
  end
end
