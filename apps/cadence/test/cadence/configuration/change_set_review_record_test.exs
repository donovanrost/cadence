defmodule Cadence.Configuration.ChangeSetReviewRecordTest do
  @moduledoc """
  #117 step 2 (P3; var/four-eyes-record-design.md; DECISIONS #112; domain's five points): a change
  set's decision row is a complete four-eyes record, provable from the row alone. Its subject
  (version and the digest of the ops it decided, which the apply asserts), its policy, the ids the
  separation check compared (#599), and admin_mode. A direct apply writes its own not_required
  row in the apply's transaction. Revisions record submitted_by, and applied_by is whoever ran
  the apply. The landing guard refuses while review rows exist.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Configuration.{ChangeSetStore, ReviewRecord, ReviewRow, RevisionRow}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.{ActivationPolicy, DecisionRecord}
  alias Cadence.Management.Activations

  setup do
    org = "org-record-117-#{System.unique_integer([:positive])}"
    mid = "mission-record-117-#{System.unique_integer([:positive])}"
    {craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    author = Fixtures.user_scope(org, "author")
    reviewer = Fixtures.user_scope(org, "reviewer")

    policy(author, mid, "direct")
    configure(author, mission, craft, revision.catalog_revision_id)

    %{org: org, mission: mission, author: author, reviewer: reviewer, craft: craft}
  end

  test "an approved review records its subject, policy, separated_from and admin_mode; the apply asserts it",
       c do
    policy(c.author, c.mission.mission_id, "independent")
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
    ops = ChangeSetStore.staged_ops(staged.change_set_id)
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

    assert {:ok, %{state: :applied, revision: number}} =
             Configuration.review(
               c.reviewer,
               c.mission.mission_id,
               staged.change_set_id,
               :approve,
               %{
                 expected_version: version
               }
             )

    assert [review] = reviews(staged)

    assert %ReviewRow{
             decision: "approved",
             subject_version: ^version,
             admin_mode: true,
             policy_document: %{"approval_required" => true}
           } = review

    assert review.subject_digest == ReviewRecord.digest(ops)
    # #599: exactly what the separation check compared, the submitter and the change's author.
    assert review.separated_from == [c.author.user.user_id]
    assert review.actor["id"] == c.reviewer.user.user_id

    # applied_by is whoever ran the apply (the reviewer), and submitted_by is the submitter.
    revision =
      Repo.one!(
        from(r in RevisionRow,
          where: r.revision_number == ^number and r.mission_id == ^c.mission.mission_id
        )
      )

    assert revision.applied_by["id"] == c.reviewer.user.user_id
    assert revision.submitted_by["id"] == c.author.user.user_id

    assert [%DecisionRecord{decision: :approved, subject: subject, admin_mode: true} | _] =
             ReviewRecord.decisions(c.org)

    assert subject == %{
             kind: "change_set",
             id: staged.change_set_id,
             version: version,
             digest: review.subject_digest,
             previous_digest: nil
           }
  end

  test "a send back records the same fields, with its comment", c do
    policy(c.author, c.mission.mission_id, "independent")
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

    assert {:ok, %{state: :open}} =
             Configuration.review(
               c.reviewer,
               c.mission.mission_id,
               staged.change_set_id,
               :send_back,
               %{
                 expected_version: version,
                 comment: "Not on a pass day"
               }
             )

    assert [
             %ReviewRow{
               decision: "sent_back",
               comment: "Not on a pass day",
               subject_version: ^version
             } = row
           ] =
             reviews(staged)

    assert row.separated_from == [c.author.user.user_id]
    assert byte_size(row.subject_digest) == 64
  end

  test "a direct apply writes its own not_required record, in the apply's transaction", c do
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
    ops = ChangeSetStore.staged_ops(staged.change_set_id)
    assert {:ok, %{state: :applied}} = submit(c, staged)

    assert [
             %ReviewRow{
               decision: "not_required",
               comment: nil,
               separated_from: [],
               admin_mode: true
             } = row
           ] =
             reviews(staged)

    assert row.subject_digest == ReviewRecord.digest(ops)
    assert row.actor["id"] == c.author.user.user_id
    assert row.policy_document["approval_required"] == false

    # The change set's read lists reviewer decisions only (the console decodes approved | sent_back).
    {:ok, set} = Configuration.change_set(c.author, c.mission.mission_id, staged.change_set_id)
    assert set.reviews == []
  end

  test "an apply whose ops don't match the reviewed digest is refused, nothing written" do
    assert {:error, :change_set_changed} =
             ReviewRecord.decided(%{}, %{}, [], %{digest: String.duplicate("0", 64)}, "review")
  end

  test "golden: the digest's canonical term is pinned (#108)" do
    op = %{
      change_id: "change-1",
      position: 0,
      kind: "spacecraft",
      entity_id: "craft-1",
      action: "update",
      payload: %{"changes" => [%{"path" => "commanding_enabled", "value" => false}]},
      base: %{"commanding_enabled" => true}
    }

    assert ReviewRecord.digest([%{op: op}]) ==
             "314373b72d91a73e0fb117bf904f568722ab37a0f6bab03e25b98a419724071b"
  end

  test "decisions/2 pages with a before cursor, newest first", c do
    for _ <- 1..3 do
      {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
      {:ok, _} = submit(c, staged)
      {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", true)])
      {:ok, _} = submit(c, staged)
    end

    all = ReviewRecord.decisions(c.org)
    assert length(all) == 6
    [first, second | _] = all

    page =
      ReviewRecord.decisions(c.org, before: {first.decided_at, review_id_of(first)}, limit: 1)

    assert [^second] = page
  end

  test "the landing guard refuses while any review row exists, before any DDL", c do
    assert {:ok, _} = Repo.query(ReviewRecord.landing_guard_sql())

    # One real row: a direct apply's not_required record.
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
    assert {:ok, %{state: :applied}} = submit(c, staged)

    assert {:error, %Postgrex.Error{postgres: %{message: message}}} =
             Repo.query(ReviewRecord.landing_guard_sql())

    assert message =~ "mission_config_reviews has 1 row(s)"
    assert message =~ "dev reset"
  end

  defp review_id_of(%DecisionRecord{} = record) do
    Repo.one!(
      from(r in ReviewRow,
        where: r.decided_at == ^record.decided_at and r.change_set_id == ^record.subject.id,
        select: r.review_id
      )
    )
  end

  defp reviews(staged),
    do: Repo.all(from(r in ReviewRow, where: r.change_set_id == ^staged.change_set_id))

  defp policy(scope, mid, requirement) do
    policy = ActivationPolicy.load(scope.organization_id, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => requirement}
      })
  end

  defp switch_op(id, path, value),
    do: %{
      kind: "spacecraft",
      action: :update,
      entity_id: id,
      changes: [%{path: path, value: value}]
    }

  defp stage(c, ops),
    do: Configuration.stage(c.author, c.mission.mission_id, %{summary: "Switches"}, ops)

  defp submit(c, staged) do
    Configuration.submit(c.author, c.mission.mission_id, staged.change_set_id, %{
      reason: "Record test",
      expected_version: staged.version,
      acknowledged_holds: true
    })
  end

  defp configure(scope, mission, craft, catalog) do
    current = Drafts.snapshot(mission, craft)

    document =
      Map.merge(SpacecraftConfigurationInput.empty(), %{
        "catalog_revision_id" => catalog,
        "telemetry_enabled" => true,
        "commanding_enabled" => true,
        "handled_apids" => [42]
      })

    :ok =
      Fixtures.change_set_switches!(
        scope.organization_id,
        mission.mission_id,
        craft.spacecraft_id,
        document
      )

    {:ok, _} =
      Drafts.save(scope, mission.mission_id, craft.spacecraft_id, current.token, document)

    token = Drafts.snapshot(mission, craft).token

    {:ok, request} =
      Review.request_many(scope, mission.mission_id, %{craft.spacecraft_id => token})

    {:ok, approved} = Activations.fetch_approved(request.activation_request_id)
    {:ok, %{status: :succeeded}} = ControlActivations.execute(approved)
  end
end
