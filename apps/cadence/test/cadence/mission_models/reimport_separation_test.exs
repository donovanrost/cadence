defmodule Cadence.MissionModels.ReimportSeparationTest do
  @moduledoc """
  Identical content is ONE mission-model revision (#119, director 11-17 option (a)). A reimport of
  the same artifact compiles to the revision that already exists, and its run says so
  (`matched_existing`). Whoever ran a completed import that produced the revision imported it
  (`Catalog.ModelImporters`), so the model gate's separation counts every importer of the content.
  A decided revision stays decided. Only completed runs in that mission count, and only user
  actors. Every run here goes through the real import path.
  """
  use Cadence.DataCase, async: false

  import Ecto.Query

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Auth.Scope
  alias Cadence.Catalog
  alias Cadence.Catalog.{Actor, Artifact, ImportRunRow, Reimport}
  alias Cadence.Catalog.RevisionRow, as: CatalogRevisionRow
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{Comparison, RevisionRow}
  alias Cadence.Reads.Catalog.{MatchedRevision, RunMatches}
  alias Cadence.Reads.CatalogOverview
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

  test "B reimports A's content: the same revision; A and B are both refused; C approves", c do
    reimporter = scope(c.organization, "reimporter-b")
    run = reimport!(reimporter, c)

    assert run.result_document["mission_model"]["revision_id"] == c.model

    assert run.result_document["mission_model"]["matched_existing"] == %{
             "revision_id" => c.model,
             "status" => "candidate"
           }

    assert importers(c, c.model) == ["importer-a", "reimporter-b"]
    report = compare!(c, c.model)

    for refused <- [c.importer, reimporter] do
      assert {:error, :mission_model_self_approval_forbidden} =
               approve(refused, c, c.model, report)
    end

    assert {:ok, %{status: :approved}} =
             approve(scope(c.organization, "admin-c"), c, c.model, report)
  end

  # Domain's ruling (#119, 11-19): an upload matching a revision of the SAME catalog database
  # makes no catalog revision; the uploader is an importer through the completed run.
  test "B uploads A's file again into the same catalog: no new revision; A and B refused; C approves",
       c do
    uploader = scope(c.organization, "uploader-b")
    {:ok, actor} = Actor.from_scope(uploader)
    run = upload!(c, c.revision.catalog_database_id, actor, "bus-again.yaml")

    assert {:error, _none} = Catalog.fetch_revision_by_import_run(c.org, c.mid, run.import_run_id)
    assert catalog_revision_count(c.revision.catalog_database_id) == 1

    assert %{
             "revision_id" => model,
             "status" => "candidate",
             "catalog_revision" => %{"revision_number" => number}
           } = run.result_document["mission_model"]["matched_existing"]

    assert {model, number} == {c.model, c.revision.revision_number}
    assert importers(c, c.model) == ["importer-a", "uploader-b"]
    report = compare!(c, c.model)

    for refused <- [c.importer, uploader] do
      assert {:error, :mission_model_self_approval_forbidden} =
               approve(refused, c, c.model, report)
    end

    assert {:ok, %{status: :approved}} =
             approve(scope(c.organization, "admin-c"), c, c.model, report)

    # The runs table: B's run matched rev 1, live (now approved); A's own run made rev 1.
    %{database: %{import_runs: rows}} =
      CatalogOverview.index(c.org, c.mid, c.revision.catalog_database_id)

    by_run = Map.new(rows, &{&1.id, &1.matched})

    assert %{number: 1, status: "approved", model_revision_id: model, first: %{number: 1}} =
             by_run[run.import_run_id]

    assert model == c.model
    assert by_run[c.revision.import_run_id] == nil
  end

  test "the same bytes into a second catalog database: its rev 1, naming the same model revision",
       c do
    {:ok, actor} = Actor.from_scope(scope(c.organization, "uploader-b"))

    other =
      Fixtures.persist_imported_revision!(c.org, c.mid,
        approve: false,
        artifact_name: "renamed.yaml",
        requested_by: actor
      )

    refute other.catalog_database_id == c.revision.catalog_database_id
    assert other.revision_number == 1
    assert other.mission_model_revision_id == c.model
    assert importers(c, c.model) == ["importer-a", "uploader-b"]

    # Its runs table: the run made this database's rev 1, and is the same as the first-recorded
    # revision of the other database (ux's "Same as Bus catalog rev 4").
    %{database: %{import_runs: [row]}} =
      CatalogOverview.index(c.org, c.mid, other.catalog_database_id)

    first_database = c.revision.catalog_database_id

    assert %{
             number: 1,
             status: "candidate",
             model_revision_id: model,
             first: %{number: 1, database: %{id: ^first_database, name: name}}
           } = row.matched

    assert model == c.model and is_binary(name)
  end

  test "a runs table's matches cost the same queries for one matched run as for three", c do
    database_id = c.revision.catalog_database_id
    one = [upload!(c, database_id, Actor.system("test:q", "Q"), "q1.yaml")]

    three =
      one ++
        for(n <- 2..3, do: upload!(c, database_id, Actor.system("test:q", "Q"), "q#{n}.yaml"))

    assert queries(fn -> put_matches(c, one) end) == queries(fn -> put_matches(c, three) end)
  end

  test "an upload matching a rejected revision makes none and says it matched rejected", c do
    admin = scope(c.organization, "admin-c")
    assert {:ok, _} = MissionModels.reject_revision(admin, c.mid, c.model, "Wrong FSW build.")

    run =
      upload!(c, c.revision.catalog_database_id, Actor.system("test:upload", "Test"), "x.yaml")

    assert catalog_revision_count(c.revision.catalog_database_id) == 1

    assert %{"revision_id" => model, "status" => "rejected"} =
             run.result_document["mission_model"]["matched_existing"]

    assert model == c.model
  end

  test "the approval read agrees with the gate", c do
    reimporter = scope(c.organization, "reimporter-b")
    reimport!(reimporter, c)

    assert {:ok, %{viewer_is_importer: true, cannot_decide_because: "self_approval"}} =
             MissionModelApprovals.read(reimporter, c.mid, c.model)

    assert {:ok, %{viewer_is_importer: false} = read} =
             MissionModelApprovals.read(scope(c.organization, "admin-c"), c.mid, c.model)

    refute read.cannot_decide_because == "self_approval"
  end

  test "a decided revision stays decided: a later import matches it and changes nothing", c do
    report = compare!(c, c.model)
    admin = scope(c.organization, "admin-c")
    assert {:ok, %{status: :approved}} = approve(admin, c, c.model, report)
    decided = stored_decision(c.model)

    # Repeated identical imports. (The sandbox serialises these on one connection; the race between
    # two real transactions is Postgres ON CONFLICT DO NOTHING: the second waits on the key, then
    # inserts nothing. Neither path writes status or a decision.)
    runs =
      for user <- ["reimporter-b", "reimporter-d"] do
        reimport!(scope(c.organization, user), c)
      end

    for run <- runs do
      assert run.result_document["mission_model"]["matched_existing"] == %{
               "revision_id" => c.model,
               "status" => "approved"
             }
    end

    assert stored_decision(c.model) == decided
  end

  test "a rejected revision stays rejected: re-importing its content doesn't reopen it", c do
    admin = scope(c.organization, "admin-c")
    assert {:ok, _rejected} = MissionModels.reject_revision(admin, c.mid, c.model, "wrong build")
    decided = stored_decision(c.model)

    run = reimport!(scope(c.organization, "reimporter-b"), c)

    assert run.result_document["mission_model"]["matched_existing"] == %{
             "revision_id" => c.model,
             "status" => "rejected"
           }

    assert stored_decision(c.model) == decided
  end

  test "C3's matched revision is the gate's live answer, per viewer (U99)", c do
    run = reimport!(scope(c.organization, "reimporter-b"), c)
    admin = scope(c.organization, "admin-c")

    assert %{
             model_revision_id: model,
             revision: %{number: 1, database: %{id: database_id, name: name}},
             status: "candidate",
             decision: nil,
             cannot_approve: %{reason: "self", via_service: nil, service: nil}
           } = MatchedRevision.read(c.importer, c.mid, run)

    assert {model, database_id} == {c.model, c.revision.catalog_database_id}
    assert is_binary(name)
    assert %{cannot_approve: nil} = MatchedRevision.read(admin, c.mid, run)

    assert {:ok, _} = MissionModels.reject_revision(admin, c.mid, c.model, "Wrong FSW build.")

    # Read live: the same run now shows the later decision, by name only.
    assert %{
             status: "rejected",
             decision: %{kind: "rejected", by: by, at: %DateTime{}, reason: "Wrong FSW build."},
             cannot_approve: nil
           } = MatchedRevision.read(c.importer, c.mid, run)

    assert by == %{name: "admin-c"}

    {:ok, first} = Catalog.fetch_import_run(c.org, c.mid, c.revision.import_run_id)
    assert MatchedRevision.read(admin, c.mid, first) == nil
  end

  test "a failed run counts no one", c do
    run = reimport!(scope(c.organization, "reimporter-b"), c)

    # A run can fail after its result is written (its catalog revision couldn't be made): only the
    # status changes on the row the real import path wrote.
    {1, _} =
      ImportRunRow
      |> where([row], row.import_run_id == ^run.import_run_id)
      |> Repo.update_all(set: [status: "failed"])

    assert importers(c, c.model) == ["importer-a"]
  end

  test "another mission's read, or a service or system actor's run, counts no one", c do
    other_mission = "mission-model-reimport-other-#{System.unique_integer([:positive])}"
    persist_mission_scope(c.org, other_mission)
    assert Catalog.model_importers(c.org, other_mission, c.model) == []

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
      assert run.result_document["mission_model"]["revision_id"] == c.model
    end

    assert importers(c, c.model) == ["importer-a"]
  end

  test "the same content in another organization or mission is its own revision", c do
    other_org = "org-model-reimport-other-#{System.unique_integer([:positive])}"
    other_mid = "mission-model-reimport-other-#{System.unique_integer([:positive])}"
    persist_mission_scope(other_org, other_mid)
    same_org_mid = "mission-model-reimport-sibling-#{System.unique_integer([:positive])}"
    persist_mission_scope(c.org, same_org_mid)

    for {org, mid} <- [{other_org, other_mid}, {c.org, same_org_mid}] do
      other = Fixtures.persist_imported_revision!(org, mid, approve: false)
      refute other.mission_model_revision_id == c.model

      assert %{organization_id: ^org, mission_id: ^mid} =
               Repo.get!(RevisionRow, other.mission_model_revision_id)
    end

    assert %{organization_id: org, mission_id: mid} = Repo.get!(RevisionRow, c.model)
    assert {org, mid} == {c.org, c.mid}
  end

  defp reimport!(scope, c) do
    assert {:ok, %{"import_run_id" => run_id}} =
             Reimport.execute(scope, c.mid, c.revision.artifact_id)

    assert {:ok, %{status: :completed} = run} = Catalog.execute_enqueued_run(run_id)
    run
  end

  defp upload!(c, database_id, requested_by, name) do
    artifact =
      Artifact.new(%{
        mission_id: c.mid,
        catalog_database_id: database_id,
        catalog_family: :combined,
        artifact_name: name,
        format_key: "cadence_yaml",
        media_type: "application/yaml",
        source_artifact: Fixtures.default_catalog_yaml()
      })

    {:ok, run} =
      Catalog.start_revision_import(c.org, c.mid, database_id, artifact, "cadence_yaml",
        metadata: %{"revision_label" => "Again"},
        requested_by: requested_by
      )

    assert {:ok, %{status: :completed} = run} = Catalog.execute_enqueued_run(run.import_run_id)
    run
  end

  defp catalog_revision_count(database_id),
    do:
      Repo.aggregate(
        from(row in CatalogRevisionRow, where: row.catalog_database_id == ^database_id),
        :count
      )

  defp put_matches(c, runs) do
    rows = Enum.map(runs, &%{id: &1.import_run_id})
    RunMatches.put(rows, runs, c.org, c.mid, c.revision.catalog_database_id)
  end

  defp queries(fun) do
    ref = make_ref()
    me = self()
    handler = "run-matches-queries-#{inspect(ref)}"

    :telemetry.attach(handler, [:cadence, :repo, :query], fn _, _, _, _ -> send(me, ref) end, nil)
    fun.()
    :telemetry.detach(handler)
    count_messages(ref, 0)
  end

  defp count_messages(ref, n) do
    receive do
      ^ref -> count_messages(ref, n + 1)
    after
      0 -> n
    end
  end

  defp stored_decision(model) do
    row = Repo.get!(RevisionRow, model)
    Map.take(row, [:status, :approved_by, :approved_at, :rejected_by, :rejected_at])
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
