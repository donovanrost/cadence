defmodule Cadence.MissionModels.SeparationTest do
  @moduledoc """
  `RevisionDecisions.separation/4` is the importer/approver separation check approval itself runs
  (DECISIONS #92 a), and the approval read calls it rather than repeating it. For each policy and
  viewer, the three answers agree: separation/4, the read's `self_approval`, and approving.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.Actor
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{Comparison, RevisionDecisions, RevisionRow}
  alias Cadence.Reads.MissionModelApprovals

  setup do
    org = "org-model-separation-#{System.unique_integer([:positive])}"
    mid = "mission-model-separation-#{System.unique_integer([:positive])}"
    %{organization: organization} = persist_mission_scope(org, mid)
    importer = scope(organization, "importer-a")
    {:ok, actor} = Actor.from_scope(importer)
    revision = Fixtures.persist_imported_revision!(org, mid, approve: false, requested_by: actor)

    %{
      org: org,
      mid: mid,
      importer: importer,
      other: scope(organization, "admin-c"),
      model: revision.mission_model_revision_id
    }
  end

  test "independent: the importer is refused by all three; another admin by none", c do
    assert {:refused, %{reason: :self, via_service: nil, service: nil}} =
             RevisionDecisions.separation(c.org, c.mid, c.model, "importer-a")

    assert read_reason(c.importer, c) == "self_approval"
    assert {:error, :mission_model_self_approval_forbidden} = approve(c.importer, c)

    assert {:ok, %{policy: policy, importers: ["importer-a"]}} =
             RevisionDecisions.separation(c.org, c.mid, c.model, "admin-c")

    refute read_reason(c.other, c) == "self_approval"
    assert {:ok, %{status: :approved}} = approve(c.other, c)

    # Approval records the policy separation/4 checked.
    assert Repo.get!(RevisionRow, c.model).approved_by["value"]["policy"] == policy
  end

  test "direct: the importer may approve, and all three agree", c do
    policy = ActivationPolicy.load(c.org, c.mid)

    assert {:ok, _} =
             ActivationPolicy.save(c.other, c.mid, policy.token, %{
               "value" => %{"approval_requirement" => "direct"}
             })

    assert {:ok, %{importers: ["importer-a"]}} =
             RevisionDecisions.separation(c.org, c.mid, c.model, "importer-a")

    refute read_reason(c.importer, c) == "self_approval"
    assert {:ok, %{status: :approved}} = approve(c.importer, c)
  end

  test "no person (nil) is never refused for separation", c do
    assert {:ok, _checked} = RevisionDecisions.separation(c.org, c.mid, c.model, nil)
  end

  defp read_reason(scope, c) do
    {:ok, read} = MissionModelApprovals.read(scope, c.mid, c.model)
    read.cannot_decide_because
  end

  defp approve(scope, c) do
    {:ok, report} = Comparison.run(c.org, c.mid, c.model, "separation-binding", 1)
    MissionModels.approve_revision(scope, c.mid, c.model, report["comparison_report_id"])
  end

  defp scope(organization, user_id) do
    Scope.new(%{
      user:
        User.new(%{user_id: user_id, email: "#{user_id}@example.test", display_name: user_id}),
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership:
        OrganizationMembership.new(%{
          user_id: user_id,
          organization_id: organization.organization_id,
          role: :organization_admin
        })
    })
  end
end
