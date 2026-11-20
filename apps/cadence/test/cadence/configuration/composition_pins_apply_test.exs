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
  alias Cadence.MissionModels.{Compositions, PinBackfill}

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

  # #112, no shim: a set submitted before D3 recorded nothing, so an apply that selects anything
  # is refused and the set must be re-staged.
  test "a set submitted before D3 (no selections recorded) is refused restage_needed", c do
    {:ok, staged} = stage(c, [switch_op(c.craft.spacecraft_id, false)])
    assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

    Repo.query!(
      "UPDATE mission_config_change_sets SET selections = NULL WHERE change_set_id = $1",
      [staged.change_set_id]
    )

    assert {:error, {:restage_needed, [%{recorded_revision_id: nil}]}} =
             approve(c, staged, version)

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

  # ca-security and domain on #544 (the table on the issue): profile changes staged before the pin
  # migration never apply unpinned. A rename applies onto the migrated profile and keeps its pin
  # (accepted: only what was reviewed applies); a catalog change (untranslated, pre-D3) is refused
  # as it disagrees with the migrated pin; a delete is refused stale; a generation, restage_needed.
  describe "a profile change staged before the pin migration" do
    test "a rename applies onto the migrated profile, keeping its composition", c do
      profile = unpinned_profile!(c)
      {:ok, staged} = stage(c, [profile_update(profile, "display_name", "Renamed")])
      assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

      PinBackfill.run(Repo)

      assert {:ok, %{state: :applied}} = approve(c, staged, version)

      assert {:ok, %{display_name: "Renamed", composition_id: composition}} =
               Cadence.SpacecraftTypeStore.fetch_spacecraft_type(c.org, c.mid, profile)

      assert composition == c.composition
    end

    test "a catalog change staged before D3 is refused: it disagrees with the migrated pin", c do
      profile = unpinned_profile!(c)
      rev2 = Fixtures.persist_imported_revision!(c.org, c.mid, revision_label: "Rev 2")

      {:ok, staged} =
        stage(c, [profile_update(profile, "catalog_revision_id", rev2.catalog_revision_id)])

      untranslate!(staged)
      assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

      PinBackfill.run(Repo)

      assert {:error, _refused} = approve(c, staged, version)
      assert_not_applied(c, staged, profile)
    end

    test "a delete staged before the pin migration is refused stale", c do
      profile = unpinned_profile!(c)

      {:ok, staged} =
        stage(c, [%{kind: "spacecraft_profile", action: :delete, entity_id: profile}])

      assert {:ok, %{state: :in_review, version: version}} = submit(c, staged)

      PinBackfill.run(Repo)

      assert {:error, _stale} = approve(c, staged, version)
      assert_not_applied(c, staged, profile)
    end
  end

  # Refused at the approve (a validation or stale refusal records why on the set): never applied,
  # and the profile is as the migration left it.
  defp assert_not_applied(c, staged, profile) do
    assert {:ok, %{state: state, applied_revision_number: nil}} =
             ChangeSetStore.fetch(c.mid, staged.change_set_id)

    refute state == "applied"

    assert {:ok, %{catalog_revision_id: catalog, composition_id: composition}} =
             Cadence.SpacecraftTypeStore.fetch_spacecraft_type(c.org, c.mid, profile)

    assert {catalog, composition} == {c.catalog.catalog_revision_id, c.composition}
  end

  # As before D3 landed: the profile's pin unfilled (the migration fills it later).
  defp unpinned_profile!(c) do
    profile = profile!(c)

    Repo.query!(
      "UPDATE mission_spacecraft_types SET composition_id = NULL WHERE spacecraft_type_id = $1",
      [profile]
    )

    profile
  end

  # As staged before D3: the staged op carries no translated composition_id change.
  defp untranslate!(staged) do
    Repo.query!(
      """
      UPDATE mission_config_ops
      SET payload = jsonb_set(payload, '{changes}',
        (SELECT coalesce(jsonb_agg(c), '[]'::jsonb) FROM jsonb_array_elements(payload->'changes') c
         WHERE c->>'path' <> 'composition_id'))
      WHERE change_set_id = $1
      """,
      [staged.change_set_id]
    )
  end

  defp profile_update(profile, path, value),
    do: %{
      kind: "spacecraft_profile",
      action: :update,
      entity_id: profile,
      changes: [%{path: path, value: value}]
    }

  ## Fixtures

  # A profile pinned to the fixture's catalog, applied through review (the policy is independent).
  defp profile!(c) do
    id = "profile-pins-apply-#{System.unique_integer([:positive])}"

    op = %{
      kind: "spacecraft_profile",
      action: :create,
      entity_id: id,
      document: %{
        "display_name" => "Pinned",
        "downlink_protocol" => "tm",
        "uplink_protocol" => "tc",
        "catalog_revision_id" => c.catalog.catalog_revision_id,
        "frame_parameters" => %{"frame_size" => 1115, "ocf_length" => 4}
      }
    }

    {:ok, staged} = stage(c, [op])
    {:ok, %{state: :in_review, version: version}} = submit(c, staged)
    {:ok, %{state: :applied}} = approve(c, staged, version)
    id
  end

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
