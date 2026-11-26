defmodule Cadence.Configuration.ChangeSetApproveRefusalsTest do
  @moduledoc """
  #262: approving a change set in review answers every refusal its checks can give, never a
  CaseClauseError (a 500). A blocking hold that appeared after the submit answers `holds_blocking`
  with the preview, and a preview that couldn't run answers `preview_failed`. Either way nothing
  is written: the set stays in review, at its version, and can be approved once the cause clears.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Configuration.ChangeSetStore
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations

  setup do
    org = "org-approve-262-#{System.unique_integer([:positive])}"
    mid = "mission-approve-262-#{System.unique_integer([:positive])}"
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

  test "a blocking hold that appeared after the submit refuses the approve; nothing is written",
       c do
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

    in_flight = request!(c, "released", verification_state: "pending")

    assert {:error, {:holds_blocking, %{checks: checks}}} = approve(c, staged, version)

    assert Enum.any?(
             Enum.flat_map(checks, & &1.items),
             &(&1[:reason] == :commanding_command_in_flight and &1[:blocking] == true)
           )

    assert_unchanged(c, staged, version)

    Repo.query!(
      "UPDATE command_requests SET verification_state = 'satisfied' WHERE command_request_id = $1",
      [in_flight]
    )

    assert {:ok, %{state: :applied}} = approve(c, staged, version)
  end

  test "a preview that can't run refuses the approve as preview_failed; nothing is written", c do
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, "commanding_enabled", false)])
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

    # The preview's own transaction hits a database error (Preview.run's rescue). DDL is
    # transactional, so the rename lives only inside this test's sandbox.
    Repo.query!("ALTER TABLE command_requests RENAME TO command_requests_262")
    result = approve(c, staged, version)
    Repo.query!("ALTER TABLE command_requests_262 RENAME TO command_requests")

    assert {:error, {:preview_failed, _message}} = result
    assert_unchanged(c, staged, version)
    assert {:ok, %{state: :applied}} = approve(c, staged, version)
  end

  defp assert_unchanged(c, staged, version) do
    assert {:ok, %{state: "in_review", version: ^version, failure_document: nil}} =
             ChangeSetStore.fetch(c.mission.mission_id, staged.change_set_id)

    assert {:ok, %{head: %{revision: 1}}} = Configuration.current(c.author, c.mission.mission_id)
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

  defp approve(c, staged, version) do
    Configuration.review(c.reviewer, c.mission.mission_id, staged.change_set_id, :approve, %{
      comment: "Looks right",
      expected_version: version
    })
  end

  defp request!(c, state, opts) do
    id = "command-request-#{System.unique_integer([:positive])}"

    Repo.query!(
      """
      INSERT INTO command_requests (command_request_id, organization_id, mission_id,
        source_endpoint_ref, mission_model_revision_id, command_id, command_name, lifecycle_state,
        verification_state, command_group_id, group_target_index, group_position, requested_at,
        inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, 'model', 'command', 'NOOP', $5, $6, $7, 0, 0, now(), now(), now())
      """,
      [
        id,
        c.org,
        c.mission.mission_id,
        c.endpoint.source_endpoint_id,
        state,
        Keyword.get(opts, :verification_state),
        Cadence.CommandMemberFixtures.group!(c.org, c.mission.mission_id)
      ]
    )

    id
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
