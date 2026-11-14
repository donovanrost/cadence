defmodule Cadence.Contacts.LostReservationContactTest do
  @moduledoc """
  Director 11-14: a reservation that won't fly releases its contact by whichever path it got there.
  A provider configuration failure (recorded as a provider error) used to leave the pass's
  scheduled contact 'scheduled', and it opened a listener for a pass no provider flew. The repair
  finds contacts left open that way and releases them through the same code path.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Contacts

  alias Cadence.Contacts.{
    ContactStore,
    ProviderReservationReconciler,
    ProviderReservations,
    ReservationContactRepair
  }

  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.ProviderChangeFixtures, as: Fixtures
  alias Cadence.Repo

  test "a provider configuration failure cancels the pass's scheduled contact, with its reason" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
    assert %{lifecycle_state: :scheduled} = scheduled(c)

    assert {:error, {:provider_configuration_failure, failed, _reason}} =
             Fixtures.advance(c, 2, %{
               "delivery_descriptor" =>
                 Map.put(descriptor(c.reservation), "endpoint_ref", "unapproved-endpoint")
             })

    assert failed.lifecycle_state == :failed

    contact = scheduled(c)
    assert contact.lifecycle_state == :canceled
    assert contact.metadata["cause"] == "provider_failed"
    assert contact.metadata["provider_reservation_id"] == c.reservation.provider_reservation_id
    assert contact.metadata["provider_reason"] == nil

    assert contact.metadata["provider_reason_code"] ==
             "delivery_descriptor_conflicts_with_transport"
  end

  test "the repair lists a lost reservation's open contact, releases it, then finds nothing" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
    reservation_id = c.reservation.provider_reservation_id

    # As before 11-14: the reservation failed by a recorded error, its contact left 'scheduled'.
    {1, _} =
      from(row in ProviderReservationRow,
        where: row.provider_reservation_id == ^reservation_id
      )
      |> Repo.update_all(set: [lifecycle_state: "failed"])

    assert {:ok,
            [
              %{
                provider_reservation_id: ^reservation_id,
                contact_state: "scheduled",
                action: "cancel"
              }
            ]} = ReservationContactRepair.run(c.organization_id, c.mission_id)

    # The dry run changes nothing.
    assert %{lifecycle_state: :scheduled} = scheduled(c)

    assert {:ok, [%{provider_reservation_id: ^reservation_id, result: "released"}]} =
             ReservationContactRepair.run(c.organization_id, c.mission_id, apply: true)

    assert %{lifecycle_state: :canceled} = scheduled(c)
    assert {:ok, []} = ReservationContactRepair.run(c.organization_id, c.mission_id)
  end

  test "a reconciler cycle releases a lost reservation's contact left open" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
    reservation_id = c.reservation.provider_reservation_id

    # As if the release had failed after the transition committed: failed, contact still open.
    {1, _} =
      from(row in ProviderReservationRow, where: row.provider_reservation_id == ^reservation_id)
      |> Repo.update_all(set: [lifecycle_state: "failed"])

    assert {:ok, _summary} =
             ProviderReservationReconciler.reconcile_due(c.organization_id,
               mission_id: c.mission_id
             )

    assert %{lifecycle_state: :canceled} = scheduled(c)
  end

  test "a reservation that still flies is never listed" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})

    assert {:ok, reservation} =
             ProviderReservations.fetch(
               c.organization_id,
               c.mission_id,
               c.reservation.provider_reservation_id
             )

    refute ProviderReservations.lost?(reservation)
    assert {:ok, []} = ReservationContactRepair.run(c.organization_id, c.mission_id)
  end

  describe "a realized contact" do
    test "not started yet is closed with its scheduled contact" do
      c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
      realized = realized_in!(c, :defined)

      fail_by_configuration!(c)

      assert %{lifecycle_state: :canceled} = scheduled(c)
      assert {:ok, %{lifecycle_state: :stopped}} = fetch_realized(c, realized)
    end

    test "already running keeps running to its LOS" do
      c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
      realized = realized_in!(c, :active)

      fail_by_configuration!(c)

      assert %{lifecycle_state: :realized} = scheduled(c)
      assert {:ok, %{lifecycle_state: :active}} = fetch_realized(c, realized)
      assert {:ok, []} = ReservationContactRepair.run(c.organization_id, c.mission_id)
    end
  end

  # The pass realized, in `state`, with no runtime left running (realizing starts one; it's stopped
  # at once so its listener frees the fixture's port).
  defp realized_in!(c, state) do
    {:ok, realized} =
      Contacts.realize_scheduled_contact(
        c.organization_id,
        c.mission_id,
        c.reservation.scheduled_contact_id,
        []
      )

    _ = Cadence.Runtime.terminate_realized_contact(c.mission_id, realized.realized_contact_id)
    {:ok, realized} = ContactStore.update_realized_lifecycle(realized, state, %{})
    realized
  end

  defp fail_by_configuration!(c) do
    {:error, {:provider_configuration_failure, %{lifecycle_state: :failed}, _reason}} =
      Fixtures.advance(c, 2, %{
        "delivery_descriptor" =>
          Map.put(descriptor(c.reservation), "endpoint_ref", "unapproved-endpoint")
      })
  end

  defp fetch_realized(c, realized),
    do: ContactStore.fetch_realized(c.organization_id, c.mission_id, realized.realized_contact_id)

  defp scheduled(c) do
    {:ok, contact} =
      Contacts.fetch_scheduled_contact(
        c.organization_id,
        c.mission_id,
        c.reservation.scheduled_contact_id
      )

    contact
  end

  # The fixture transport's delivery, active 30 s either side of the pass.
  defp descriptor(reservation) do
    %{
      "direction" => "downlink",
      "delivery_kind" => "realtime_stream",
      "mode" => "provider_connects",
      "protocol" => "tcp",
      "endpoint_ref" => reservation.delivery_profile_ref["id"],
      "framing" => %{"family" => "ccsds_tm", "frame_bytes" => 1115},
      "allowed_source_refs" => [reservation.provider_spacecraft_ref],
      "credential_ref" => nil,
      "activation_window" => %{
        "starts_at" => reservation.starts_at |> DateTime.add(-30) |> DateTime.to_iso8601(),
        "ends_at" => reservation.ends_at |> DateTime.add(30) |> DateTime.to_iso8601()
      }
    }
  end
end
