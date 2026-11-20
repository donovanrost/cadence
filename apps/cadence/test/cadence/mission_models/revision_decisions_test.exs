defmodule Cadence.MissionModels.RevisionDecisionsTest do
  @moduledoc """
  The approval a mission-model revision needs before a generation may introduce it (DECISIONS #92
  (a), director 11-15): an organization administrator, the comparison report they saw, and under
  'independent' approval someone other than its importer.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{Comparison, RevisionRow}
  alias Cadence.Persistence.JsonDocument

  setup do
    org = "org-model-decisions-#{System.unique_integer([:positive])}"
    mid = "mission-model-decisions-#{System.unique_integer([:positive])}"
    %{organization: organization} = persist_mission_scope(org, mid)
    admin = scope(organization, "admin-a", :organization_admin)
    %{org: org, mid: mid, organization: organization, admin: admin}
  end

  test "an administrator approves with the comparison report they saw", c do
    revision = import!(c)
    report = compare!(c, revision)

    assert {:ok, %{status: :approved}} =
             MissionModels.approve_revision(
               c.admin,
               c.mid,
               revision,
               report["comparison_report_id"]
             )

    approved_by = RevisionRow |> Repo.get!(revision) |> Map.get(:approved_by)

    assert %{
             "kind" => "user",
             "id" => "admin-a",
             "comparison_report_id" => id,
             "replay" => "not_run",
             # The fixture's system actor names its runner (#513), so an importer is on record.
             "importer_recorded" => true
           } = JsonDocument.unwrap_value(approved_by)

    assert id == report["comparison_report_id"]
  end

  test "a mission's first revision, with no configuration yet, compares against nothing and is approved",
       c do
    revision = import!(c, requested_by: %{"user_id" => "admin-a"})

    # No activation, so no binding set: the comparison records none, and no baseline.
    assert {:ok, report} =
             Comparison.run(c.org, c.mid, revision, nil, nil, baseline_revision_id: nil)

    assert %{"status" => "passed", "baseline_revision_id" => nil, "binding_set_id" => nil} =
             report

    assert report["binding_set_version"] == nil
    assert report["replay"]["status"] in ["not_run", "not_required"]
    assert report["static"]["added"] != []

    # The same comparison again is the same report.
    assert {:ok, %{"comparison_report_id" => id}} =
             Comparison.run(c.org, c.mid, revision, nil, nil, baseline_revision_id: nil)

    assert id == report["comparison_report_id"]

    assert {:error, :mission_model_self_approval_forbidden} =
             MissionModels.approve_revision(c.admin, c.mid, revision, id)

    other = scope(c.organization, "admin-b", :organization_admin)

    assert {:ok, %{status: :approved}} =
             MissionModels.approve_revision(other, c.mid, revision, id)
  end

  test "members and services can't decide", c do
    revision = import!(c)
    report = compare!(c, revision)
    member = scope(c.organization, "member-a", :member)
    service = %{c.admin | actor_kind: :service}

    assert {:error, _forbidden} =
             MissionModels.approve_revision(
               member,
               c.mid,
               revision,
               report["comparison_report_id"]
             )

    assert {:error, :human_mission_model_approver_required} =
             MissionModels.approve_revision(
               service,
               c.mid,
               revision,
               report["comparison_report_id"]
             )

    assert {:error, _forbidden} = MissionModels.reject_revision(member, c.mid, revision, "No")
  end

  test "another revision's comparison report doesn't count", c do
    revision = import!(c)
    other = import!(c, revision_label: "Rev 2", yaml: other_yaml())
    report = compare!(c, other)

    assert {:error, :mission_model_comparison_mismatch} =
             MissionModels.approve_revision(
               c.admin,
               c.mid,
               revision,
               report["comparison_report_id"]
             )
  end

  test "under 'independent' approval the importer can't approve; another administrator can", c do
    revision = import!(c, requested_by: %{"user_id" => "admin-a"})
    report = compare!(c, revision)

    assert {:error, :mission_model_self_approval_forbidden} =
             MissionModels.approve_revision(
               c.admin,
               c.mid,
               revision,
               report["comparison_report_id"]
             )

    other = scope(c.organization, "admin-b", :organization_admin)

    assert {:ok, %{status: :approved}} =
             MissionModels.approve_revision(
               other,
               c.mid,
               revision,
               report["comparison_report_id"]
             )
  end

  test "each decision records the approval policy in force at decision time", c do
    revision = import!(c, requested_by: %{"user_id" => "admin-a"})
    report = compare!(c, revision)
    other = scope(c.organization, "admin-b", :organization_admin)

    assert {:ok, %{status: :approved}} =
             MissionModels.approve_revision(
               other,
               c.mid,
               revision,
               report["comparison_report_id"]
             )

    approved_by = RevisionRow |> Repo.get!(revision) |> Map.get(:approved_by)

    assert %{
             "policy" =>
               %{"policy" => "scoped_activation_approvals_v1", "separation_of_duties" => true} =
                 policy
           } = JsonDocument.unwrap_value(approved_by)

    assert policy == ActivationPolicy.evidence(c.org, c.mid)

    # A rejection under 'direct' records that policy (no separation) and its settings version.
    current = ActivationPolicy.load(c.org, c.mid)

    {:ok, _} =
      ActivationPolicy.save(c.admin, c.mid, current.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    second = import!(c, revision_label: "Rev 2", yaml: other_yaml())

    assert {:ok, %{status: :rejected}} =
             MissionModels.reject_revision(c.admin, c.mid, second, "No")

    rejected_by = RevisionRow |> Repo.get!(second) |> Map.get(:rejected_by)

    assert %{"policy" => %{"separation_of_duties" => false, "settings_token" => token}} =
             JsonDocument.unwrap_value(rejected_by)

    assert token == ActivationPolicy.load(c.org, c.mid).token
    refute token == policy["settings_token"]
  end

  test "under 'direct' approval the importer may approve", c do
    policy = ActivationPolicy.load(c.org, c.mid)

    {:ok, _} =
      ActivationPolicy.save(c.admin, c.mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    revision = import!(c, requested_by: %{"user_id" => "admin-a"})
    report = compare!(c, revision)

    assert {:ok, %{status: :approved}} =
             MissionModels.approve_revision(
               c.admin,
               c.mid,
               revision,
               report["comparison_report_id"]
             )
  end

  test "rejecting needs a reason, records who did, and only rejects a candidate", c do
    revision = import!(c)

    assert {:error, :mission_model_decision_reason_required} =
             MissionModels.reject_revision(c.admin, c.mid, revision, "  ")

    assert {:ok, %{status: :rejected}} =
             MissionModels.reject_revision(c.admin, c.mid, revision, "Wrong APIDs")

    rejected_by = RevisionRow |> Repo.get!(revision) |> Map.get(:rejected_by)

    assert %{"kind" => "user", "id" => "admin-a", "reason" => "Wrong APIDs"} =
             JsonDocument.unwrap_value(rejected_by)

    assert {:error, :mission_model_revision_not_approvable} =
             MissionModels.reject_revision(c.admin, c.mid, revision, "Again")

    approved = import!(c, revision_label: "Rev 2", yaml: other_yaml())
    report = compare!(c, approved)

    {:ok, _} =
      MissionModels.approve_revision(c.admin, c.mid, approved, report["comparison_report_id"])

    assert {:error, :mission_model_revision_not_approvable} =
             MissionModels.reject_revision(c.admin, c.mid, approved, "Changed my mind")
  end

  test "an approval and a rejection at once: exactly one decides", c do
    revision = import!(c)
    report = compare!(c, revision)
    other = scope(c.organization, "admin-b", :organization_admin)

    results =
      [:approve, :reject]
      |> Task.async_stream(
        fn
          :approve ->
            MissionModels.approve_revision(
              c.admin,
              c.mid,
              revision,
              report["comparison_report_id"]
            )

          :reject ->
            MissionModels.reject_revision(other, c.mid, revision, "Not this one")
        end,
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _revision}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :mission_model_revision_not_approvable})) == 1
  end

  test "approving again keeps the first approver; a reason has a length limit", c do
    revision = import!(c)
    report = compare!(c, revision)
    other = scope(c.organization, "admin-b", :organization_admin)

    {:ok, _} =
      MissionModels.approve_revision(c.admin, c.mid, revision, report["comparison_report_id"])

    {:ok, _} =
      MissionModels.approve_revision(other, c.mid, revision, report["comparison_report_id"])

    approved_by = RevisionRow |> Repo.get!(revision) |> Map.get(:approved_by)
    assert %{"id" => "admin-a"} = JsonDocument.unwrap_value(approved_by)

    candidate = import!(c, revision_label: "Rev 2", yaml: other_yaml())

    assert {:error, :mission_model_decision_reason_too_long} =
             MissionModels.reject_revision(
               c.admin,
               c.mid,
               candidate,
               String.duplicate("x", 2_001)
             )
  end

  test "people's decisions are listed for the audit, fixtures' aren't", c do
    revision = import!(c)
    report = compare!(c, revision)

    {:ok, _} =
      MissionModels.approve_revision(c.admin, c.mid, revision, report["comparison_report_id"])

    fixture = import!(c, revision_label: "Rev 2", yaml: other_yaml())
    Cadence.MissionModelApproval.approve!(c.org, c.mid, fixture)

    assert [
             %{
               revision_id: ^revision,
               decision: :approved,
               by: %{"id" => "admin-a"},
               evidence: evidence
             }
           ] =
             MissionModels.list_model_decisions(c.org, c.mid)

    assert evidence["replay"] == "not_run"
    assert evidence["retroactive"] == false
  end

  test "a retroactive approval says so", c do
    revision = import!(c)
    report = compare!(c, revision)

    {:ok, _} =
      MissionModels.approve_revision(c.admin, c.mid, revision, report["comparison_report_id"],
        retroactive: true
      )

    assert [%{evidence: %{"retroactive" => true}}] =
             MissionModels.list_model_decisions(c.org, c.mid)
  end

  defp import!(c, opts \\ []) do
    Fixtures.persist_imported_revision!(c.org, c.mid, Keyword.put(opts, :approve, false)).mission_model_revision_id
  end

  defp compare!(c, revision) do
    {:ok, report} = Comparison.run(c.org, c.mid, revision, "decisions-binding", 1)
    report
  end

  defp other_yaml do
    """
    packets:
      - name: OTHER
        apid: 43
        items:
          - name: level
            data_type: uint
            bit_offset: 0
            bit_size: 8
    commands: []
    """
  end

  defp scope(organization, user_id, role) do
    user =
      User.new(%{
        user_id: user_id,
        email: "#{user_id}@example.test",
        display_name: user_id
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership:
        OrganizationMembership.new(%{
          user_id: user_id,
          organization_id: organization.organization_id,
          role: role
        })
    })
  end
end
