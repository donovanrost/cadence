defmodule Cadence.Contacts.ProviderChangeApprovalsTest do
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Auth.Scope

  alias Cadence.Contacts.{
    ProviderChangeApprovals,
    ProviderReservationChanges,
    ScheduledContactRevisions
  }

  alias Cadence.GroundNetworks.{
    ProviderAccount,
    ProviderAccountGrant,
    ProviderAccountVersion,
    ProviderAudit
  }

  alias Cadence.Persistence.Schemas.{
    ProviderAccountGrantRow,
    ProviderAccountRow,
    ProviderAccountVersionRow,
    ProviderReservationChangeRow,
    ProviderReservationRow,
    ScheduledContactRow
  }

  alias Cadence.ProviderChangeFixtures
  alias Cadence.Repo

  test "an organization admin approves the exact proposal and appends one revision" do
    context = pending_change()
    change = only_change(context)

    assert {:ok, result} =
             ProviderChangeApprovals.approve(
               context.admin_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "Shift remains inside the flight plan"
             )

    assert result.change.lifecycle_state == :approved
    assert result.provider_change_approval.decision == :approved
    assert result.provider_change_approval.actor_user_id == context.admin_scope.user.user_id
    assert result.scheduled_contact.current_revision == 2
    assert result.scheduled_contact_revision.revision == 2

    assert {:ok, approval} =
             ProviderChangeApprovals.fetch(
               context.organization_id,
               change.provider_reservation_change_id
             )

    assert approval.reason == "Shift remains inside the flight plan"

    assert [audit] =
             ProviderAudit.list_entries(context.organization_id,
               provider_change_id: change.provider_reservation_change_id
             )

    assert audit.action == "provider_change.approved"
  end

  test "stale hash and superseded revision cannot be approved" do
    context = pending_change()
    first = only_change(context)

    assert {:error, :stale_provider_change_proposal} =
             ProviderChangeApprovals.approve(
               context.admin_scope,
               first.provider_reservation_change_id,
               String.duplicate("0", 64),
               "Stale browser submission"
             )

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
               "The provider has already replaced this proposal"
             )
  end

  test "a proposal past its provider decision deadline cannot be approved" do
    context = ProviderChangeFixtures.setup_contact()
    deadline = ~U[2026-07-15 18:30:00.000000Z]

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(context, 2, %{
               "starts_at" => ProviderChangeFixtures.shift(context.baseline["starts_at"], 60),
               "ends_at" => ProviderChangeFixtures.shift(context.baseline["ends_at"], 60),
               "extensions" => %{
                 "provider_change" => %{"deadline_at" => DateTime.to_iso8601(deadline)}
               }
             })

    change = only_change(context)

    assert {:error, :provider_change_decision_deadline_passed} =
             ProviderChangeApprovals.approve(
               context.admin_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "The provider deadline has elapsed",
               now: DateTime.add(deadline, 1)
             )
  end

  test "rejection is recorded only while the provider can still honor it" do
    context = pending_change()
    change = only_change(context)

    assert {:ok, rejected} =
             ProviderChangeApprovals.reject(
               context.admin_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "The shifted pass conflicts with commanding"
             )

    assert rejected.lifecycle_state == :rejected

    not_rejectable = ProviderChangeFixtures.setup_contact()

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(not_rejectable, 2, %{
               "starts_at" =>
                 ProviderChangeFixtures.shift(not_rejectable.baseline["starts_at"], 60),
               "ends_at" => ProviderChangeFixtures.shift(not_rejectable.baseline["ends_at"], 60),
               "extensions" => %{"provider_change" => %{"rejectable" => false}}
             })

    change = only_change(not_rejectable)

    assert {:error, :provider_change_not_rejectable} =
             ProviderChangeApprovals.reject(
               not_rejectable.admin_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "This should fail closed"
             )
  end

  test "already-effective facts are acknowledged instead of approved" do
    context = ProviderChangeFixtures.setup_contact()

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(context, 2, %{
               "status" => "canceled",
               "extensions" => %{"provider_change" => %{"effective" => true}}
             })

    change = only_change(context)

    assert {:error, {:provider_change_not_decidable, "acknowledgment_required"}} =
             ProviderChangeApprovals.approve(
               context.admin_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "Approval is the wrong semantic"
             )

    assert {:ok, acknowledged} =
             ProviderChangeApprovals.acknowledge(
               context.admin_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "Flight has incorporated the provider cancellation"
             )

    assert acknowledged.lifecycle_state == :acknowledged
  end

  test "application rechecks policy, grant, and pre-realization state" do
    policy_context = pending_change()
    policy_change = only_change(policy_context)

    from(row in ProviderReservationChangeRow,
      where: row.provider_reservation_change_id == ^policy_change.provider_reservation_change_id
    )
    |> Repo.update_all(set: [policy_version: policy_change.policy_version + 1])

    assert {:error, :provider_change_policy_superseded} =
             ProviderChangeApprovals.approve(
               policy_context.admin_scope,
               policy_change.provider_reservation_change_id,
               policy_change.proposal_hash,
               "Policy changed"
             )

    grant_context = pending_change()
    grant_change = only_change(grant_context)
    bind_revoked_grant!(grant_context)

    assert {:error, :provider_account_grant_revoked} =
             ProviderChangeApprovals.approve(
               grant_context.admin_scope,
               grant_change.provider_reservation_change_id,
               grant_change.proposal_hash,
               "Grant must remain active"
             )

    realized_context = pending_change()
    realized_change = only_change(realized_context)

    from(row in ScheduledContactRow,
      where: row.scheduled_contact_id == ^realized_context.reservation.scheduled_contact_id
    )
    |> Repo.update_all(set: [lifecycle_state: "realized", realized_contact_id: "realized-1"])

    assert {:error, :scheduled_contact_realization_started} =
             ProviderChangeApprovals.approve(
               realized_context.admin_scope,
               realized_change.provider_reservation_change_id,
               realized_change.proposal_hash,
               "Too late to rewrite execution"
             )
  end

  test "the apply transaction rolls back approval, schedule, revision, and audit together" do
    context = pending_change()
    change = only_change(context)

    assert {:error, :injected_provider_change_apply_failure} =
             ProviderChangeApprovals.approve(
               context.admin_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "Exercise rollback",
               fail_before_commit?: true
             )

    assert {:error, :provider_change_approval_not_found} =
             ProviderChangeApprovals.fetch(
               context.organization_id,
               change.provider_reservation_change_id
             )

    assert [revision] =
             ScheduledContactRevisions.list(
               context.organization_id,
               context.reservation.scheduled_contact_id
             )

    assert revision.revision == 1
    assert only_change(context).lifecycle_state == :pending_approval

    assert [] ==
             ProviderAudit.list_entries(context.organization_id,
               provider_change_id: change.provider_reservation_change_id
             )
  end

  test "concurrent approval attempts produce exactly one decision and revision" do
    context = pending_change()
    change = only_change(context)

    results =
      1..2
      |> Task.async_stream(
        fn attempt ->
          ProviderChangeApprovals.approve(
            context.admin_scope,
            change.provider_reservation_change_id,
            change.proposal_hash,
            "Concurrent approval #{attempt}"
          )
        end,
        max_concurrency: 2,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _result}, &1)) == 1
    assert Enum.count(results, &match?({:error, _reason}, &1)) == 1

    assert [initial, accepted] =
             ScheduledContactRevisions.list(
               context.organization_id,
               context.reservation.scheduled_contact_id
             )

    assert initial.revision == 1
    assert accepted.revision == 2
  end

  test "approval requires an authenticated organization-admin user" do
    context = pending_change()
    change = only_change(context)
    %Scope{} = admin_scope = context.admin_scope
    member_scope = %Scope{admin_scope | capabilities: MapSet.new(), role: :member}
    service_scope = %Scope{admin_scope | actor_kind: :service, user: nil}

    assert {:error, :forbidden} =
             ProviderChangeApprovals.approve(
               member_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "Members cannot approve"
             )

    assert {:error, :authenticated_user_required} =
             ProviderChangeApprovals.approve(
               service_scope,
               change.provider_reservation_change_id,
               change.proposal_hash,
               "Service identities cannot approve"
             )
  end

  defp pending_change do
    context = ProviderChangeFixtures.setup_contact()

    assert {:ok, _reservation} =
             ProviderChangeFixtures.advance(context, 2, %{
               "starts_at" => ProviderChangeFixtures.shift(context.baseline["starts_at"], 60),
               "ends_at" => ProviderChangeFixtures.shift(context.baseline["ends_at"], 60)
             })

    context
  end

  defp only_change(context) do
    assert [change] =
             ProviderReservationChanges.list_for_reservation(
               context.organization_id,
               context.reservation.provider_reservation_id
             )

    change
  end

  defp bind_revoked_grant!(context) do
    account_id = "provider-account-#{context.reservation.provider_reservation_id}"
    grant_id = "provider-grant-#{context.reservation.provider_reservation_id}"
    now = ~U[2026-07-15 18:00:00.000000Z]

    account =
      ProviderAccount.new(%{
        provider_account_id: account_id,
        organization_id: context.organization_id,
        display_name: "Revoked test account",
        lifecycle_state: :active,
        active_version: 1,
        credential_status: :active,
        event_ingestion_status: :healthy
      })

    version =
      ProviderAccountVersion.new(%{
        provider_account_id: account_id,
        organization_id: context.organization_id,
        version: 1,
        provider_type: :simulator,
        base_url: "http://simulator.test",
        environment_ref: "run-revoked",
        credential_ref: "config://simulator",
        created_at: now
      })

    active_grant =
      ProviderAccountGrant.new(%{
        provider_account_grant_id: grant_id,
        organization_id: context.organization_id,
        mission_id: context.mission_id,
        provider_account_id: account_id,
        provider_account_version: 1,
        version: 1,
        lifecycle_state: :active,
        granted_at: now
      })

    revoked_grant =
      ProviderAccountGrant.new(%{
        active_grant
        | version: 2,
          lifecycle_state: :revoked,
          revoked_by: context.admin_scope.user.user_id,
          revoked_at: DateTime.add(now, 1),
          revoke_reason: "Test revocation"
      })

    {:ok, _row} = account |> ProviderAccountRow.changeset() |> Repo.insert()
    {:ok, _row} = version |> ProviderAccountVersionRow.changeset() |> Repo.insert()
    {:ok, _row} = active_grant |> ProviderAccountGrantRow.changeset() |> Repo.insert()

    from(row in ProviderReservationRow,
      where: row.provider_reservation_id == ^context.reservation.provider_reservation_id
    )
    |> Repo.update_all(
      set: [
        provider_account_id: account_id,
        provider_account_version: 1,
        provider_account_grant_id: grant_id,
        provider_account_grant_version: 1
      ]
    )

    {:ok, _row} = revoked_grant |> ProviderAccountGrantRow.changeset() |> Repo.insert()
  end
end
