defmodule Cadence.MissionModels.ReimportSeparationTest do
  @moduledoc """
  Whoever ran a completed import of a mission-model revision imported it (director/lead 11-17,
  option A; `Catalog.ModelImporters`). Every import run makes its own model revision (the
  declarations' provenance carries the run id), so a reimport, which makes no catalog revision,
  makes an orphan model revision that only its run names: its runner is that revision's importer,
  and the original revision's importers don't change. Only completed runs in that mission count,
  and only user actors. Every run here is written by the real import path, so the stored
  documents' wrapping is exercised.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.{Actor, ImportRunRow, Reimport}
  alias Cadence.MissionModels
  alias Cadence.MissionModels.Comparison
  alias Cadence.Reads.MissionModelApprovals

  setup do
    org = "org-model-reimport-#{System.unique_integer([:positive])}"
    mid = "mission-model-reimport-#{System.unique_integer([:positive])}"
    %{organization: organization} = persist_mission_scope(org, mid)
    importer = scope(organization, "importer-a")
    {:ok, actor} = Actor.from_scope(importer)
    revision = Fixtures.persist_imported_revision!(org, mid, approve: false, requested_by: actor)

    %{
      org: org,
      mid: mid,
      organization: organization,
      importer: importer,
      revision: revision,
      model: revision.mission_model_revision_id
    }
  end

  test "a reimporting admin is refused on the revision their reimport made; another approves",
       c do
    reimporter = scope(c.organization, "reimporter-b")
    {_run_id, orphan} = reimport!(reimporter, c)

    assert importers(c, orphan) == ["reimporter-b"]
    assert importers(c, c.model) == ["importer-a"]

    assert {:error, :mission_model_self_approval_forbidden} =
             approve(reimporter, c, orphan, compare!(c, orphan))

    assert {:ok, %{status: :approved}} =
             approve(scope(c.organization, "admin-c"), c, orphan, compare!(c, orphan))

    # The original stays its importer's: a reimport doesn't change who imported it.
    report = compare!(c, c.model)

    assert {:error, :mission_model_self_approval_forbidden} =
             approve(c.importer, c, c.model, report)

    assert {:ok, %{status: :approved}} = approve(reimporter, c, c.model, report)
  end

  test "the approval read agrees with the gate", c do
    reimporter = scope(c.organization, "reimporter-b")
    {_run_id, orphan} = reimport!(reimporter, c)

    assert {:ok, %{viewer_is_importer: true, cannot_decide_because: "self_approval"}} =
             MissionModelApprovals.read(reimporter, c.mid, orphan)

    assert {:ok, %{viewer_is_importer: false, imported_by: %{id: "reimporter-b"}} = read} =
             MissionModelApprovals.read(scope(c.organization, "admin-c"), c.mid, orphan)

    refute read.cannot_decide_because == "self_approval"
  end

  test "a failed run counts no one", c do
    {run_id, orphan} = reimport!(scope(c.organization, "reimporter-b"), c)

    # A run can fail after its result is written (its catalog revision couldn't be made): only the
    # status changes on the row the real import path wrote.
    {1, _} =
      ImportRunRow
      |> where([run], run.import_run_id == ^run_id)
      |> Repo.update_all(set: [status: "failed"])

    assert importers(c, orphan) == []
  end

  test "another mission's read, or a service or system actor's run, counts no one", c do
    {_run_id, orphan} = reimport!(scope(c.organization, "reimporter-b"), c)
    other_mission = "mission-model-reimport-other-#{System.unique_integer([:positive])}"
    persist_mission_scope(c.org, other_mission)
    assert c.org |> Catalog.model_importers(other_mission, orphan) == []

    service = %{
      "actor_kind" => "service",
      "service_identity_id" => "svc-reimport",
      "name" => "Pipeline"
    }

    for requested_by <- [service, Actor.system("test:reimport", "Reimport test")] do
      {:ok, run} =
        Catalog.start_import_run(c.org, c.mid, c.revision.artifact_id, "cadence_yaml",
          requested_by: requested_by
        )

      {:ok, %{status: :completed} = run} = Catalog.execute_enqueued_run(run.import_run_id)
      assert importers(c, run.result_document["mission_model"]["revision_id"]) == []
    end
  end

  defp reimport!(scope, c) do
    assert {:ok, %{"import_run_id" => run_id}} =
             Reimport.execute(scope, c.mid, c.revision.artifact_id)

    assert {:ok, %{status: :completed} = run} = Catalog.execute_enqueued_run(run_id)
    orphan = run.result_document["mission_model"]["revision_id"]
    assert is_binary(orphan) and orphan != c.model
    {run_id, orphan}
  end

  defp importers(c, model), do: c.org |> Catalog.model_importers(c.mid, model) |> Enum.sort()

  defp approve(scope, c, model, report),
    do: MissionModels.approve_revision(scope, c.mid, model, report["comparison_report_id"])

  defp compare!(c, model) do
    {:ok, report} = Comparison.run(c.org, c.mid, model, "reimport-binding", 1)
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
