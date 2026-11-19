defmodule Cadence.Contacts.LostReservationContactTest do
  @moduledoc """
  Director 11-14: a reservation that won't fly releases its contact by whichever path it got there.
  A provider configuration failure (recorded as a provider error) used to leave the pass's
  scheduled contact 'scheduled', and it opened a listener for a pass no provider flew. The repair
  finds contacts left open that way and releases them through the same code path.
  """
  # RuntimeCase (shared sandbox): closing a realized contact starts its settler, a runtime
  # process that records the settlement in the database (#270).
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Contacts

  alias Cadence.Contacts.{
    ContactSettler,
    ContactStore,
    ProviderReservationReconciler,
    ProviderReservations,
    ReservationContactRepair
  }

  alias Cadence.Control.Contacts.Store.ProviderReservationRow
  alias Cadence.ProviderChangeFixtures, as: Fixtures
  alias Cadence.Repo

  # Director 11-14: a failure from Cadence's own checks isn't the provider letting the pass go.
  # 008's and 007's flew (~134k observations) after Cadence 'failed' them.
  test "a configuration failure keeps the pass's contact: the provider may still fly it" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
    failed = fail_by_configuration!(c)

    assert ProviderReservations.cadence_side_failure?(failed)
    refute ProviderReservations.lost?(failed)
    assert %{lifecycle_state: :scheduled} = scheduled(c)

    # The repair shows it as a recheck, never a cancel.
    reservation_id = c.reservation.provider_reservation_id

    assert {:ok,
            [
              %{
                provider_reservation_id: ^reservation_id,
                action: "recheck",
                source: "provider_reservation_validation"
              }
            ]} = ReservationContactRepair.run(c.organization_id, c.mission_id)
  end

  test "the provider's own failed status cancels the contact, with its words and code" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
    provider_failed!(c)

    contact = scheduled(c)
    assert contact.lifecycle_state == :canceled
    assert contact.metadata["cause"] == "provider_failed"
    assert contact.metadata["provider_reservation_id"] == c.reservation.provider_reservation_id
    assert contact.metadata["provider_reason"] == "no antenna available"
    assert contact.metadata["provider_reason_code"] == "no_antenna"
  end

  describe "a provisional (Cadence-side) failure" do
    test "returns to confirmed when the provider's next answer validates" do
      c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
      fail_by_configuration!(c)

      assert {:ok, recovered} =
               Fixtures.advance(c, 3, %{"delivery_descriptor" => descriptor(c.reservation)})

      assert recovered.lifecycle_state == :confirmed
      assert recovered.last_error_document == %{}
      assert %{lifecycle_state: :scheduled} = scheduled(c)
    end

    # api-ops' re-review: the provider's next answer may be its own loss.
    test "becomes rejected when the provider rejects it, and its contact is released" do
      c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
      fail_by_configuration!(c)

      assert {:ok, %{lifecycle_state: :rejected} = rejected} =
               Fixtures.advance(c, 3, %{
                 "status" => "rejected",
                 "status_reason" => %{
                   "category" => "no_capacity",
                   "detail" => "antenna reassigned"
                 },
                 "delivery_descriptor" => descriptor(c.reservation)
               })

      assert ProviderReservations.lost?(rejected)
      assert %{lifecycle_state: :canceled} = contact = scheduled(c)
      assert contact.metadata["cause"] == "provider_rejected"
      assert contact.metadata["provider_reason"] == "antenna reassigned"
    end

    test "can go back to pending when the provider re-queues it" do
      c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
      fail_by_configuration!(c)

      assert {:ok, %{lifecycle_state: :pending}} =
               Fixtures.advance(c, 3, %{
                 "status" => "pending",
                 "delivery_descriptor" => descriptor(c.reservation)
               })

      assert %{lifecycle_state: :scheduled} = scheduled(c)
    end

    test "is polled until its pass ends, then settles as failed with its reason" do
      c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
      fail_by_configuration!(c)
      reservation_id = c.reservation.provider_reservation_id
      before_los = DateTime.add(c.reservation.ends_at, -60)
      after_los = DateTime.add(c.reservation.ends_at, 60)

      assert reservation_id in due_ids(c, before_los)
      refute reservation_id in due_ids(c, after_los)

      {:ok, settled} = ProviderReservations.fetch(c.organization_id, c.mission_id, reservation_id)
      assert settled.lifecycle_state == :failed
      assert settled.last_error_document["source"] == "provider_reservation_validation"

      assert settled.last_error_document["reason"] =~
               "delivery_descriptor_conflicts_with_transport"
    end
  end

  test "the provider's own failure stays terminal and isn't polled" do
    c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
    provider_failed!(c)
    refute c.reservation.provider_reservation_id in due_ids(c, DateTime.utc_now())

    assert {:error, {:invalid_provider_reservation_transition, :failed, :confirmed}} =
             Fixtures.advance(c, 3, %{
               "status" => "confirmed",
               "delivery_descriptor" => descriptor(c.reservation)
             })
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

      provider_failed!(c)

      assert %{lifecycle_state: :canceled} = scheduled(c)
      assert {:ok, %{lifecycle_state: :stopped}} = fetch_realized(c, realized)

      # Stopping it hands it to its settler (DECISIONS #71), which records the settlement in the
      # background: wait for that, so the settler doesn't outlive this test's sandbox (#270).
      await_settled(c, realized)
    end

    test "already running keeps running to its LOS" do
      c = Fixtures.setup_contact(%{}, baseline: &%{"delivery_descriptor" => descriptor(&1)})
      realized = realized_in!(c, :active)

      provider_failed!(c)

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
    {:error, {:provider_configuration_failure, %{lifecycle_state: :failed} = failed, _reason}} =
      Fixtures.advance(c, 2, %{
        "delivery_descriptor" =>
          Map.put(descriptor(c.reservation), "endpoint_ref", "unapproved-endpoint")
      })

    failed
  end

  # The provider itself fails the pass, with its own reason.
  defp provider_failed!(c) do
    {:ok, %{lifecycle_state: :failed}} =
      Fixtures.advance(c, 2, %{
        "status" => "failed",
        "status_reason" => %{"category" => "no_antenna", "detail" => "no antenna available"},
        "delivery_descriptor" => descriptor(c.reservation)
      })
  end

  defp due_ids(c, due_before) do
    c.organization_id
    |> ProviderReservations.list_due_for_reconciliation(
      mission_id: c.mission_id,
      due_before: due_before
    )
    |> Enum.map(& &1.provider_reservation_id)
  end

  defp await_settled(c, realized, tries \\ 250)

  defp await_settled(_c, realized, 0),
    do: flunk("the settler still runs for #{realized.realized_contact_id}")

  defp await_settled(c, realized, tries) do
    {:ok, contact} = fetch_realized(c, realized)

    unless contact.metadata["settlement"]["state"] in ["settled", "unsettled"] and
             not ContactSettler.settling?(c.mission_id, realized.realized_contact_id) do
      Process.sleep(20)
      await_settled(c, realized, tries - 1)
    end
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
