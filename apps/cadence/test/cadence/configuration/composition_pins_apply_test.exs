defmodule Cadence.Configuration.CompositionPinsApplyTest do
  @moduledoc """
  D3 (#544; design §3): the submit records what it selected per pinned composition, and the apply
  selects again under the activation lock. A difference refuses `restage_needed` and writes
  nothing; only what was reviewed runs.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.CompositionFixtures
  alias Cadence.Configuration.ChangeSetStore
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.{Configuration, ConfigurationSelections}
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.MissionModels.Compositions

  setup do
    org = "org-pins-apply-#{System.unique_integer([:positive])}"
    mid = "mission-pins-apply-#{System.unique_integer([:positive])}"
    {craft, revision, _endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    author = Fixtures.user_scope(org, "author")
    reviewer = Fixtures.user_scope(org, "reviewer")

    policy(author, mid, "direct")
    configure(author, mission, craft, revision.catalog_revision_id)
    policy(author, mid, "independent")

    {:ok, %{composition_id: composition}} =
      Compositions.for_revision(org, mid, revision.mission_model_revision_id)

    %{
      org: org,
      mid: mid,
      mission: mission,
      author: author,
      reviewer: reviewer,
      craft: craft,
      catalog: revision,
      revision_id: revision.mission_model_revision_id,
      composition: composition
    }
  end

  test "the submit records what it selected; an unchanged selection applies", c do
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, false)])
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

    assert {:ok, %{selections: selections}} = ChangeSetStore.fetch(c.mid, staged.change_set_id)
    assert selections[c.composition] == c.revision_id

    assert {:ok, %{state: :applied}} = approve(c, staged, version)
  end

  test "the recorded revision withdrawn while in review: restage_needed, nothing written", c do
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, false)])
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

    # The approval goes away between the review's start and the apply (E2's withdraw will do this
    # through the product; here the status moves directly in the sandbox).
    CompositionFixtures.set_status!([c.revision_id], "retired")

    assert {:error, {:restage_needed, [entry]}} = approve(c, staged, version)

    assert entry == %{
             composition_id: c.composition,
             recorded_revision_id: c.revision_id,
             current_revision_id: nil,
             current_reason: "none_left",
             # What U109's words name the pin by (display only).
             catalog_revision_number: c.catalog.revision_number,
             composition_number: entry.composition_number
           }

    assert is_integer(entry.composition_number)

    assert_unchanged(c, staged, version)
  end

  test "check: a newer approval between staging and the apply refuses restage_needed", c do
    recorded = %{c.composition => c.revision_id}
    catalogs = [c.catalog.catalog_revision_id]
    ctx = %{org: c.org, mid: c.mid, revision_id: c.revision_id, catalog: c.catalog}
    newer = CompositionFixtures.copy_revision!(ctx, "3")
    CompositionFixtures.link!(ctx, c.composition, newer)
    CompositionFixtures.set_status!([newer], "candidate")
    runnable = ["2", "3"]

    # Not yet approved: the selection is unchanged.
    assert {:ok, _} =
             ConfigurationSelections.check(c.org, c.mid, recorded, catalogs, runnable: runnable)

    CompositionFixtures.approve!(newer)

    assert {:error,
            {:restage_needed,
             [
               %{
                 recorded_revision_id: old,
                 current_revision_id: ^newer,
                 current_reason: "newer_approved"
               }
             ]}} =
             ConfigurationSelections.check(c.org, c.mid, recorded, catalogs, runnable: runnable)

    assert old == c.revision_id
  end

  test "check: the recorded revision's version no longer runs: unrunnable", c do
    recorded = %{c.composition => c.revision_id}
    catalogs = [c.catalog.catalog_revision_id]
    ctx = %{org: c.org, mid: c.mid, revision_id: c.revision_id, catalog: c.catalog}
    newer = CompositionFixtures.copy_revision!(ctx, "3")
    CompositionFixtures.link!(ctx, c.composition, newer)

    # A release drops '2' from the runnable list; '3' is approved.
    assert {:error,
            {:restage_needed, [%{current_revision_id: ^newer, current_reason: "unrunnable"}]}} =
             ConfigurationSelections.check(c.org, c.mid, recorded, catalogs, runnable: ["3"])
  end

  ## Fixtures

  defp assert_unchanged(c, staged, version) do
    assert {:ok, %{state: "in_review", version: ^version, failure_document: nil}} =
             ChangeSetStore.fetch(c.mid, staged.change_set_id)
  end

  defp policy(scope, mid, requirement) do
    policy = ActivationPolicy.load(scope.organization_id, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => requirement}
      })
  end

  defp switch_op(id, value),
    do: %{
      kind: "spacecraft",
      action: :update,
      entity_id: id,
      changes: [%{path: "commanding_enabled", value: value}]
    }

  defp stage(c, ops), do: Configuration.stage(c.author, c.mid, %{summary: "Pins apply"}, ops)

  defp submit(c, staged),
    do:
      Configuration.submit(c.author, c.mid, staged.change_set_id, %{
        reason: "Composition pins apply test",
        expected_version: staged.version,
        acknowledged_holds: true
      })

  defp approve(c, staged, version),
    do:
      Configuration.review(c.reviewer, c.mid, staged.change_set_id, :approve, %{
        comment: "Looks right",
        expected_version: version
      })

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
