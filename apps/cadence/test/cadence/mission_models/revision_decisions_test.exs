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
             "importer_recorded" => false
           } = JsonDocument.unwrap_value(approved_by)

    assert id == report["comparison_report_id"]
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

    assert {:error, _forbidden} = MissionModels.reject_revision(member, c.mid, revision)
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

  test "rejecting records who did", c do
    revision = import!(c)
    assert {:ok, %{status: :rejected}} = MissionModels.reject_revision(c.admin, c.mid, revision)
    rejected_by = RevisionRow |> Repo.get!(revision) |> Map.get(:rejected_by)
    assert %{"kind" => "user", "id" => "admin-a"} = JsonDocument.unwrap_value(rejected_by)
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
