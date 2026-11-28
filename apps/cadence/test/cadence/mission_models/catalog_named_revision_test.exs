defmodule Cadence.MissionModels.CatalogNamedRevisionTest do
  @moduledoc """
  A mission-model revision that no catalog revision names can be neither approved nor applied
  (director 11-17, interim). Every import run compiles its own model revision; a
  run that makes no catalog revision (a reimport) leaves one that no catalog revision names, and
  the model approval's importer separation is recorded against catalog revisions.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.{ModelRevisions, RevisionRow}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Activations.Resume
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModelFixtures
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
    unnamed = run_again!(c, %{"user_id" => "reimporter-b"})
    assert ModelRevisions.for_models(c.org, c.mid, [unnamed]) == %{}

    # The importer's own revision is refused to them (separation is on in this mission).
    assert {:error, :mission_model_self_approval_forbidden} = approve(c.importer, c, c.model)

    assert {:error, :mission_model_revision_not_in_catalog} = approve(c.importer, c, unnamed)
    assert {:error, :mission_model_revision_not_in_catalog} = approve(c.other_admin, c, unnamed)
  end

  test "a revision a catalog revision names is approved as before", c do
    assert {:ok, %{status: :approved}} = approve(c.other_admin, c, c.model)
  end

  test "an approved request whose revision no catalog revision names isn't applied, and isn't retried",
       c do
    assert {:ok, %{status: :approved}} = approve(c.other_admin, c, c.model)
    binding_set = persist_binding_set!(c)

    {:ok, request} =
      MissionModelFixtures.request_model_activation(
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

  # The same immutable artifact, imported again without a new catalog revision.
  defp run_again!(c, requested_by) do
    {:ok, run} =
      Catalog.start_import_run(c.org, c.mid, c.revision.artifact_id, "cadence_yaml",
        requested_by: requested_by
      )

    {:ok, %{status: :completed} = run} = Catalog.execute_enqueued_run(run.import_run_id)
    model = run.result_document["mission_model"]["revision_id"]
    assert is_binary(model) and model != c.model
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
