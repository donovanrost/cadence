defmodule Cadence.MissionModels.ServiceImporterSeparationTest do
  @moduledoc """
  #280: a revision imported through a service identity counts as imported by the service's
  accountable people (issuer and rotators). Under 'independent' they can't approve it, and the
  refusal names the service (U100 `via_service`); when nobody is on record for the service,
  nobody can approve it (`mission_model_approver_authors_unknown`). The approval read agrees.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth
  alias Cadence.Auth.{Scope, ServiceAccountableRow, ServiceIdentity}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.MissionModels
  alias Cadence.MissionModels.Comparison
  alias Cadence.Reads.MissionModelApprovals

  setup do
    org = "org-model-service-#{System.unique_integer([:positive])}"
    mid = "mission-model-service-#{System.unique_integer([:positive])}"
    %{organization: organization} = persist_mission_scope(org, mid)
    issuer = scope(organization, "issuer-a")

    {:ok, %{service_identity: service}} =
      Auth.issue_service_identity(
        ServiceIdentity.new(%{
          organization_id: org,
          mission_id: mid,
          display_name: "Catalog pipeline",
          capabilities: [:mission_admin]
        }),
        issuer
      )

    actor = %{
      "actor_kind" => "service",
      "service_identity_id" => service.service_identity_id,
      "name" => "Catalog pipeline"
    }

    revision = Fixtures.persist_imported_revision!(org, mid, approve: false, requested_by: actor)

    %{
      org: org,
      mid: mid,
      organization: organization,
      issuer: issuer,
      service: service,
      model: revision.mission_model_revision_id
    }
  end

  test "the service's issuer can't approve it, and the refusal names the service", c do
    report = compare!(c)
    id = c.service.service_identity_id

    assert {:error,
            {:mission_model_self_approval_forbidden,
             %{via_service: %{id: ^id, name: "Catalog pipeline"}}}} =
             approve(c.issuer, c, report)

    assert {:ok,
            %{
              cannot_decide_because: "self_approval",
              cannot_decide_details: %{via_service: %{id: ^id}}
            }} = MissionModelApprovals.read(c.issuer, c.mid, c.model)

    assert {:ok, %{status: :approved}} = approve(scope(c.organization, "admin-c"), c, report)
  end

  test "with nobody on record for the service, nobody can approve it", c do
    Repo.delete_all(
      from(row in ServiceAccountableRow,
        where: row.service_identity_id == ^c.service.service_identity_id
      )
    )

    report = compare!(c)
    id = c.service.service_identity_id

    for approver <- [c.issuer, scope(c.organization, "admin-c")] do
      assert {:error, {:mission_model_approver_authors_unknown, %{service: %{id: ^id}}}} =
               approve(approver, c, report)

      assert {:ok,
              %{
                cannot_decide_because: "authors_unknown",
                cannot_decide_details: %{service: %{id: ^id}}
              }} = MissionModelApprovals.read(approver, c.mid, c.model)
    end
  end

  test "under 'direct' nothing new is refused: the issuer's approval stands", c do
    policy = ActivationPolicy.load(c.org, c.mid)

    {:ok, _} =
      ActivationPolicy.save(c.issuer, c.mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    assert {:ok, %{status: :approved}} = approve(c.issuer, c, compare!(c))
  end

  defp approve(scope, c, report),
    do: MissionModels.approve_revision(scope, c.mid, c.model, report["comparison_report_id"])

  defp compare!(c) do
    {:ok, report} = Comparison.run(c.org, c.mid, c.model, "service-binding", 1)
    report
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
