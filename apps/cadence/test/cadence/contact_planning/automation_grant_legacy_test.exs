defmodule Cadence.ContactPlanning.AutomationGrantLegacyTest do
  @moduledoc """
  #497 (lead and ca-security, 11-19): a grant issued before #283 had no proposal step. The
  migration fills its proposal columns from its own approval so it stays readable, marks it
  `legacy_issue`, writes no decision, and leaves its old-layout hash, so it's still refused at
  use. This runs the migration's own fill statement against a legacy-shaped row, then re-adds
  the shape check as VALID, so the filled row provably satisfies it with nothing relaxed.
  """
  use Cadence.DataCase, async: false

  alias Cadence.AutomationGrantFixtures, as: F

  alias Cadence.ContactPlanning.{
    AutomationGrantDecisions,
    AutomationGrantReview,
    AutomationGrants
  }

  alias Cadence.Control.PlanningGrants

  @migration "priv/repo/migrations/20261120000000_automation_grant_proposals.exs"

  setup do
    c = F.setup!("grant-legacy")
    # A migration module, compiled by the migrator, not the test build: named at run time.
    migration = Module.concat(Cadence.Repo.Migrations, AutomationGrantProposals)
    unless Code.ensure_loaded?(migration), do: Code.require_file(@migration)
    Map.put(c, :fill_sql, migration.legacy_fill_sql())
  end

  test "a filled legacy grant reads as issued before two-person approval, and nothing more", c do
    id = legacy_row!(c, "active")

    assert {:ok, grant} = AutomationGrants.fetch(c.org, c.mission, id)
    assert grant.legacy_issue
    assert grant.lifecycle_state == :active
    assert grant.validity_seconds == 86_400

    # (1) No invented history: the fill writes no decision.
    assert AutomationGrantDecisions.list(c.org, c.mission, id) == []

    # (2)/(3) The console read shows the mark, never a proposer or proposal time.
    {:ok, %{grants: [row]}} = PlanningGrants.load(c.approver, c.mission)
    assert row.issued_before_two_person_approval == true
    assert row.proposed_by == nil and row.proposed_at == nil and row.proposal_expires_at == nil

    # (6) Never offered Approve; approving answers not_proposed.
    assert row.viewer_can_decide == false
    assert row.cannot_decide_because == "not_proposed"
    assert {"not_proposed", nil} = AutomationGrantReview.viewer_block(c.approver, grant, F.now())

    # (4) Still refused at use: its stored hash is the old layout.
    assert {:error, :automation_grant_hash_mismatch} =
             AutomationGrants.authorize(
               c.service_scope,
               c.mission,
               id,
               :plan,
               %{horizon_seconds: 60},
               now: F.now()
             )

    # api-ops on #497: narrowing would re-hash it in today's layout and re-arm it, so it's
    # refused with nothing written, Narrow isn't offered, and it's still refused at use.
    assert row.viewer_can_narrow == false

    assert {:error, {:automation_grant_legacy, %{}}} =
             AutomationGrants.narrow(c.third, c.mission, id, %{maximum_contacts: 1}, now: F.now())

    assert {:ok, %{content_sha256: unchanged}} = AutomationGrants.fetch(c.org, c.mission, id)
    assert unchanged == String.duplicate("e", 64)
    assert AutomationGrantDecisions.list(c.org, c.mission, id) == []

    assert {:error, :automation_grant_hash_mismatch} =
             AutomationGrants.authorize(
               c.service_scope,
               c.mission,
               id,
               :plan,
               %{horizon_seconds: 60},
               now: F.now()
             )

    for refused <- [
          fn -> AutomationGrants.approve(c.third, c.mission, id, unchanged, now: F.now()) end,
          fn -> AutomationGrants.reject(c.third, c.mission, id, "No", now: F.now()) end
        ] do
      assert {:error, {:automation_grant_legacy, %{}}} = refused.()
    end

    # (6) Revoke still works, and is recorded; the old-layout hash survives it.
    assert {:ok, %{lifecycle_state: :revoked, content_sha256: ^unchanged}} =
             AutomationGrants.revoke(c.third, c.mission, id, nil, "Before two-person approval")

    assert [%{decision: :revoked}] = AutomationGrantDecisions.list(c.org, c.mission, id)
    assert {:ok, %{content_sha256: ^unchanged}} = AutomationGrants.fetch(c.org, c.mission, id)
  end

  test "a revoked legacy grant reads too (the dev database's one row)", c do
    id = legacy_row!(c, "revoked")

    assert {:ok, %{lifecycle_state: :revoked, legacy_issue: true}} =
             AutomationGrants.fetch(c.org, c.mission, id)
  end

  # Drops the shape check inside the test's transaction (rolled back after), inserts a row as
  # pre-#283 code wrote it, runs the migration's fill, and re-adds the check VALID (ca-security's
  # point 5: the filled row must satisfy the unchanged definition).
  defp legacy_row!(c, state) do
    %{rows: [[definition]]} =
      Repo.query!(
        "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'automation_grants_state_shape'"
      )

    Repo.query!("ALTER TABLE automation_grants DROP CONSTRAINT automation_grants_state_shape")

    id = "automation_grant_legacy_#{System.unique_integer([:positive])}"
    approved_at = DateTime.add(F.now(), -3_600, :second)

    revoked =
      if state == "revoked",
        do: %{revoked_by: "admin-old", revoked_at: F.now(), revocation_reason: "Old"},
        else: %{revoked_by: nil, revoked_at: nil, revocation_reason: ""}

    Repo.insert_all(
      "automation_grants",
      [
        Map.merge(
          %{
            automation_grant_id: id,
            organization_id: c.org,
            mission_id: c.mission,
            service_identity_id: c.service.service_identity_id,
            fleet_planning_policy_id: c.policy.fleet_planning_policy_id,
            fleet_planning_policy_version: c.policy_version.version,
            allowed_actions: ["plan"],
            maximum_horizon_seconds: 3_600,
            maximum_contacts: 5,
            maximum_execution_concurrency: 1,
            valid_from: approved_at,
            valid_until: DateTime.add(approved_at, 86_400, :second),
            lifecycle_state: state,
            approved_by: c.proposer.user.user_id,
            approved_at: approved_at,
            approval_reason: "Issued before #283",
            content_sha256: String.duplicate("e", 64),
            inserted_at: approved_at,
            updated_at: approved_at
          },
          revoked
        )
      ]
    )

    Repo.query!(c.fill_sql)

    Repo.query!(
      "ALTER TABLE automation_grants ADD CONSTRAINT automation_grants_state_shape " <>
        String.replace(definition, " NOT VALID", "")
    )

    id
  end
end
