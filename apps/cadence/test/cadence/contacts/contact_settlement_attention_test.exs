defmodule Cadence.Contacts.ContactSettlementAttentionTest do
  @moduledoc "#847 (U37): one booking's open settlement item, by keyed reads (ground's #857 review)."
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{ContactSettlementAttention, ContactStore, RealizedContact}
  alias Cadence.ProviderChangeFixtures

  setup do
    c = ProviderChangeFixtures.setup_contact()
    unsettled!(c)
    c
  end

  # An ended contact whose telemetry is still on disk, for the fixture's booking.
  defp unsettled!(c) do
    now = DateTime.utc_now()

    {:ok, _contact} =
      ContactStore.persist_realized(
        RealizedContact.new(%{
          organization_id: c.organization_id,
          mission_id: c.mission_id,
          scheduled_contact_id: c.reservation.scheduled_contact_id,
          initial_time: now,
          realized_at: now,
          lifecycle_state: :completed,
          metadata: %{
            "settlement" => %{
              "state" => "unsettled",
              "reason" => "settle_deadline",
              "failure_kind" => "store_unavailable",
              "unsettled_at" => DateTime.to_iso8601(now),
              "backlog" => %{"entries" => 120, "bytes" => 4096, "journals" => 1}
            }
          }
        })
      )
  end

  describe "for_reservation/3" do
    test "answers the same item items/2 builds for that booking", c do
      assert [item] = ContactSettlementAttention.items(c.organization_id, c.mission_id)

      assert ContactSettlementAttention.for_reservation(
               c.organization_id,
               c.mission_id,
               c.reservation.provider_reservation_id
             ) == item

      assert item.provider_reservation_id == c.reservation.provider_reservation_id
    end

    test "answers nil for another mission's booking and for an unknown one", c do
      other = ProviderChangeFixtures.setup_contact()
      unsettled!(other)

      assert ContactSettlementAttention.for_reservation(
               c.organization_id,
               c.mission_id,
               other.reservation.provider_reservation_id
             ) == nil

      assert ContactSettlementAttention.for_reservation(
               c.organization_id,
               c.mission_id,
               "no-such-booking"
             ) == nil
    end
  end
end
