defmodule Cadence.Configuration.ChangeSetApproveCommentTest do
  @moduledoc """
  #521 (#313 K9, ux): a comment is optional on Approve and required only for Send back. An
  approve without one (absent, empty or whitespace) applies and records NULL, never an empty
  string: on the review, on the revision's approvals and on the change set's activation
  decision (whose `reason` is optional for approved, as DecisionRecord's rule). A comment over
  2,000 bytes is refused on either decision.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Configuration.{ReviewRow, Status}
  alias Cadence.Control.ActivationRequests.Rows
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Management.Activations.ActivationDecisionRow

  setup do
    org = "org-comment-521-#{System.unique_integer([:positive])}"
    mid = "mission-comment-521-#{System.unique_integer([:positive])}"
    {craft, revision, endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    author = Fixtures.user_scope(org, "author")
    reviewer = Fixtures.user_scope(org, "reviewer")

    policy(author, mid, "direct")
    configure(author, mission, craft, revision.catalog_revision_id)
    policy(author, mid, "independent")

    %{
      org: org,
      mission: mission,
      author: author,
      reviewer: reviewer,
      craft: craft,
      endpoint: endpoint
    }
  end

  for {label, params} <- [
        {"absent", %{}},
        {"empty", %{comment: ""}},
        {"whitespace", %{comment: "  \n "}}
      ] do
    @params params
    test "an approve with its comment #{label} applies and records no comment", c do
      {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
      assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

      assert {:ok, %{state: :applied}} = review(c, staged, :approve, version, @params)

      assert [%{decision: "approved", comment: nil}] =
               Repo.all(where(ReviewRow, change_set_id: ^staged.change_set_id))

      assert [%{approvals: [%{comment: nil}]} | _] =
               Status.list_revisions(c.org, c.mission.mission_id)

      assert [%{decision: :approved, reason: nil} = decision] =
               Repo.all(
                 from(d in ActivationDecisionRow,
                   where: d.mission_id == ^c.mission.mission_id and d.decision == :approved,
                   order_by: [desc: d.decided_at],
                   limit: 1
                 )
               )

      # The console's activation rows read it as null (activations/api.ts: reason orNull).
      {:ok, request} = Activations.fetch(c.reviewer, decision.activation_request_id)
      [row] = Rows.rows(c.reviewer, c.mission.mission_id, [request])
      assert %{state: "approved", reason: nil} = row.decision
    end
  end

  test "a send back still needs a comment", c do
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

    for params <- [%{}, %{comment: "   "}] do
      assert {:error, :comment_required} = review(c, staged, :send_back, version, params)
    end
  end

  test "a comment over 2,000 bytes is refused on either decision, by field", c do
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)
    long = %{comment: String.duplicate("a", 2_001)}

    for decision <- [:approve, :send_back] do
      assert {:error,
              {:invalid_params, %{comment: "That's too long: keep it to about 2,000 characters."}}} =
               review(c, staged, decision, version, long)
    end
  end

  test "a comment given on approve is kept", c do
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

    assert {:ok, %{state: :applied}} =
             review(c, staged, :approve, version, %{comment: "  Looks right  "})

    assert [%{comment: "Looks right"}] =
             Repo.all(where(ReviewRow, change_set_id: ^staged.change_set_id))
  end

  defp review(c, staged, decision, version, params) do
    Configuration.review(
      c.reviewer,
      c.mission.mission_id,
      staged.change_set_id,
      decision,
      Map.put(params, :expected_version, version)
    )
  end

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
      reason: "Approve refusals test",
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
