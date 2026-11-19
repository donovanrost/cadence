defmodule Cadence.MissionModels.CatalogNamedRevisionTest do
  @moduledoc """
  A mission-model revision that no catalog revision names can be neither approved nor requested
  for activation (director 11-17, interim; kept as defence in depth by #119). Since #119 a
  reimport of identical content matches the revision its catalog revision already names, so the
  unnamed revisions here are compiled directly, as a fixture without its naming helper would be.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.MissionModel.Layer
  alias Cadence.Catalog.{ModelRevisions, RevisionRow}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Activations.Resume
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModelApproval
  alias Cadence.MissionModels
  alias Cadence.MissionModels.Comparison

  setup do
    org = "org-model-named-#{System.unique_integer([:positive])}"
    mid = "mission-model-named-#{System.unique_integer([:positive])}"
    %{organization: organization} = persist_mission_scope(org, mid)

    revision =
      Fixtures.persist_imported_revision!(org, mid,
        approve: false,
        requested_by: %{"user_id" => "importer-a"}
      )

    %{
      org: org,
      mid: mid,
      importer: scope(organization, "importer-a"),
      other_admin: scope(organization, "admin-c"),
      revision: revision,
      model: revision.mission_model_revision_id
    }
  end

  test "a model revision no catalog revision names can't be approved, by anyone", c do
    unnamed = unnamed!(c)
    assert ModelRevisions.for_models(c.org, c.mid, [unnamed]) == %{}

    # The importer's own revision is refused to them (separation is on in this mission).
    assert {:error, :mission_model_self_approval_forbidden} = approve(c.importer, c, c.model)

    assert {:error, :mission_model_revision_not_in_catalog} = approve(c.importer, c, unnamed)
    assert {:error, :mission_model_revision_not_in_catalog} = approve(c.other_admin, c, unnamed)
  end

  test "an approved model revision no catalog revision names can't be requested for activation",
       c do
    unnamed = unnamed!(c)
    {:ok, _approved} = MissionModelApproval.approve!(c.org, c.mid, unnamed)
    binding_set = persist_binding_set!(c)

    assert {:error, :mission_model_revision_not_in_catalog} =
             MissionModels.request_promotion(
               c.other_admin,
               c.mid,
               unnamed,
               binding_set.binding_set_id,
               binding_set.version
             )
  end

  test "a revision a catalog revision names is approved and requested as before", c do
    assert {:ok, %{status: :approved}} = approve(c.other_admin, c, c.model)
    binding_set = persist_binding_set!(c)

    assert {:ok, %{state: _requested}} =
             MissionModels.request_promotion(
               c.other_admin,
               c.mid,
               c.model,
               binding_set.binding_set_id,
               binding_set.version
             )
  end

  test "a revision compiled without a catalog revision (a fixture missing its naming helper) is refused",
       c do
    layer =
      Layer.new(%{
        organization_id: c.org,
        mission_id: c.mid,
        name: "unnamed fixture model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    {:ok, compilation} = MissionModels.compile_layers([layer])
    unnamed = compilation.revision.revision_id
    {:ok, _approved} = MissionModelApproval.approve!(c.org, c.mid, unnamed)
    binding_set = persist_binding_set!(c)

    assert {:error, :mission_model_revision_not_in_catalog} =
             MissionModels.request_promotion(
               c.other_admin,
               c.mid,
               unnamed,
               binding_set.binding_set_id,
               binding_set.version
             )
  end

  test "an approved request whose revision no catalog revision names isn't applied, and isn't retried",
       c do
    assert {:ok, %{status: :approved}} = approve(c.other_admin, c, c.model)
    binding_set = persist_binding_set!(c)

    {:ok, request} =
      MissionModels.request_promotion(
        c.importer,
        c.mid,
        c.model,
        binding_set.binding_set_id,
        binding_set.version
      )

    {:ok, _request, _decision, approved} =
      ManagementActivations.approve(c.other_admin, request.activation_request_id, "reviewed")

    # The catalog revision that named it is gone by the time it applies.
    {1, _} =
      Repo.delete_all(
        from(row in RevisionRow,
          where: row.catalog_revision_id == ^c.revision.catalog_revision_id
        )
      )

    assert {:error, :mission_model_revision_not_in_catalog} = ControlActivations.execute(approved)
    refute Resume.retryable_code?("mission_model_revision_not_in_catalog")
  end

  # A revision no catalog revision names: compiled straight from a layer, outside an import.
  defp unnamed!(c) do
    layer =
      Layer.new(%{
        organization_id: c.org,
        mission_id: c.mid,
        name: "unnamed fixture model",
        declarations: [%{kind: :space_system, qualified_name: "/"}]
      })

    {:ok, compilation} = MissionModels.compile_layers([layer])
    model = compilation.revision.revision_id
    assert ModelRevisions.for_models(c.org, c.mid, [model]) == %{}
    assert model != c.model
    model
  end

  defp approve(scope, c, model) do
    {:ok, report} = Comparison.run(c.org, c.mid, model, "named-binding", 1)
    MissionModels.approve_revision(scope, c.mid, model, report["comparison_report_id"])
  end

  defp persist_binding_set!(c) do
    {:ok, binding_set} =
      Cadence.Governance.persist_binding_set(
        BindingSet.new(%{
          organization_id: c.org,
          mission_id: c.mid,
          binding_set_id: "named-binding",
          version: 1
        })
      )

    binding_set
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
