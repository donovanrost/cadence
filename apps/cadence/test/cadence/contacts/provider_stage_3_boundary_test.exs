defmodule Cadence.Contacts.ProviderStage3BoundaryTest do
  use Cadence.DataCase, async: false

  alias Cadence.Contacts.{
    ProviderChangeApprovals,
    ProviderReservationChanges,
    ScheduledContactRevisions
  }

  alias Cadence.ProviderChangeFixtures

  test "automatic, explicit, and already-effective changes keep distinct semantics" do
    automatic =
      ProviderChangeFixtures.setup_contact(%{
        "mode" => "bounded_automatic",
        "maximum_later_start_shift_seconds" => 30,
        "maximum_later_end_shift_seconds" => 30
      })

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(automatic, 2, %{
               "starts_at" => ProviderChangeFixtures.shift(automatic.baseline["starts_at"], 30),
               "ends_at" => ProviderChangeFixtures.shift(automatic.baseline["ends_at"], 30)
             })

    assert [automatic_change] = changes(automatic)
    assert automatic_change.lifecycle_state == :policy_accepted
    assert [_initial, accepted] = revisions(automatic)
    assert accepted.revision == 2

    explicit = ProviderChangeFixtures.setup_contact()

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(explicit, 2, %{
               "starts_at" => ProviderChangeFixtures.shift(explicit.baseline["starts_at"], 60),
               "ends_at" => ProviderChangeFixtures.shift(explicit.baseline["ends_at"], 60)
             })

    assert [explicit_change] = changes(explicit)
    assert explicit_change.lifecycle_state == :pending_approval
    assert [_initial] = revisions(explicit)

    effective = ProviderChangeFixtures.setup_contact()

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(effective, 2, %{
               "status" => "canceled",
               "extensions" => %{
                 "provider_change" => %{"effective" => true, "rejectable" => false}
               }
             })

    assert [effective_change] = changes(effective)
    assert effective_change.lifecycle_state == :acknowledgment_required
    refute effective_change.actionable
  end

  test "a superseded proposal cannot rewrite the accepted execution revision" do
    context = ProviderChangeFixtures.setup_contact()

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(context, 2, %{
               "starts_at" => ProviderChangeFixtures.shift(context.baseline["starts_at"], 60),
               "ends_at" => ProviderChangeFixtures.shift(context.baseline["ends_at"], 60)
             })

    assert [first] = changes(context)

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(context, 3, %{
               "starts_at" => ProviderChangeFixtures.shift(context.baseline["starts_at"], 120),
               "ends_at" => ProviderChangeFixtures.shift(context.baseline["ends_at"], 120)
             })

    assert {:error, {:provider_change_not_decidable, "superseded"}} =
             ProviderChangeApprovals.approve(
               context.admin_scope,
               first.provider_reservation_change_id,
               first.proposal_hash,
               "The provider has replaced this proposal"
             )

    assert [_initial] = revisions(context)
  end

  test "configuration drift fails closed before an execution revision is created" do
    context = ProviderChangeFixtures.setup_contact(%{"mode" => "bounded_automatic"})

    assert {:error, {:provider_configuration_failure, failed, _reason}} =
             ProviderChangeFixtures.advance(context, 2, %{
               "delivery_descriptor" => %{
                 "protocol" => "tcp",
                 "endpoint_ref" => "unapproved-endpoint",
                 "framing" => %{"family" => "ccsds_tm", "frame_bytes" => 1_024}
               }
             })

    assert failed.lifecycle_state == :failed
    assert [change] = changes(context)
    assert change.lifecycle_state == :configuration_failure
    assert [_initial] = revisions(context)
  end

  defp changes(context) do
    ProviderReservationChanges.list_for_reservation(
      context.organization_id,
      context.reservation.provider_reservation_id
    )
  end

  defp revisions(context) do
    ScheduledContactRevisions.list(
      context.organization_id,
      context.reservation.scheduled_contact_id
    )
  end
end
