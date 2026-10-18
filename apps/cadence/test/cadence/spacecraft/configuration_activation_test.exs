defmodule Cadence.Activations.SpacecraftConfigurationTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Activations.SpacecraftConfiguration, as: ConfigurationActivation
  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.SpacecraftConfiguration
  alias Cadence.Control.SpacecraftModelBindings
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{ComparisonReportRow, QualificationCaseRow}
  alias Cadence.Reads.Catalog.{Databases, Revisions}
  alias Cadence.Reads.Spacecraft.Configuration, as: ConfigurationRead
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.Missions, as: RuntimeMissions
  alias Cadence.Runtime.PartitionKey
  alias Cadence.Spacecraft.Identity
  alias Cadence.SpacecraftStore

  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Control.MissionModelPromotion

  alias Cadence.Applications.SpacecraftConfiguration.Active, as: ConfigurationActive
  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Applications.SpacecraftConfiguration.Review, as: ConfigurationReview
  alias Cadence.Catalog.SpacecraftConfigurationInput, as: ConfigurationInput

  alias Cadence.{Activations, Governance}

  setup do
    org = "org-spacecraft-activation"
    mission_id = "mission-spacecraft-activation"
    {first, revision, endpoint} = Fixtures.setup_imported_mission!(org, mission_id)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mission_id)
    second = Fixtures.persist_spacecraft!(org, mission_id, display_name: "Second")

    other_endpoint =
      Fixtures.persist_source_endpoint!(org, mission_id, second.spacecraft_id,
        display_name: "Second source"
      )

    other_revision =
      Fixtures.persist_imported_revision!(org, mission_id, revision_label: "Second revision")

    %{
      org: org,
      mission: mission,
      scope: Fixtures.user_scope(org, "requester"),
      first: first,
      second: second,
      revision: revision,
      other_revision: other_revision,
      endpoint: endpoint,
      other_endpoint: other_endpoint
    }
  end

  test "activating a spacecraft retains another spacecraft's active revision instead of its newer draft",
       c do
    first = save(c, c.first, c.revision)
    assert {:ok, request} = review(c, c.first)
    assert {:ok, _activation} = activate(c, request)
    second = save(c, c.second, c.other_revision)
    newer = save(c, c.first, c.other_revision)
    assert newer.version == 2
    assert {:ok, request} = review(c, c.second)
    assert {:ok, activation} = activate(c, request)
    assert {:ok, active} = ConfigurationActive.load(c.mission)

    assert active.entries[c.first.spacecraft_id]["configuration_revision_id"] ==
             first.configuration_revision_id

    assert active.entries[c.second.spacecraft_id]["configuration_revision_id"] ==
             second.configuration_revision_id

    assert {:ok, basis} = MissionModelPromotion.runtime_basis(activation)

    {:ok, spec} =
      MissionRuntimeSpec.new(
        Map.merge(basis, %{
          activation_id: activation.activation_id,
          organization_id: c.org,
          mission_id: c.mission.mission_id,
          generation: activation.generation,
          binding_set_id: active.binding_set.binding_set_id,
          binding_set_version: active.binding_set.version,
          binding_set: active.binding_set,
          activated_at: activation.activated_at
        })
      )

    for {endpoint, revision} <- [{c.endpoint, c.revision}, {c.other_endpoint, c.other_revision}] do
      assert {:ok, partition} =
               MissionRuntimeSpec.for_partition(
                 spec,
                 %PartitionKey{
                   affinity: :source_endpoint,
                   value: endpoint.source_endpoint_id
                 }
               )

      assert partition.mission_model_revision_id == revision.mission_model_revision_id

      assert Enum.all?(partition.runtime_plans, fn {_, plan} ->
               plan.mission_model_revision_id == revision.mission_model_revision_id
             end)
    end

    assert {:error, :spacecraft_model_not_active} =
             MissionRuntimeSpec.for_partition(
               spec,
               %PartitionKey{
                 affinity: :source_endpoint,
                 value: "unreviewed-source"
               }
             )

    assert :ok =
             TelemetryDecom.activation_applied(
               active.binding_set,
               activation.metadata
             )

    {:ok, first_config} =
      TelemetryDecom.fetch_config(
        c.org,
        c.mission.mission_id,
        c.first.spacecraft_id
      )

    {:ok, second_config} =
      TelemetryDecom.fetch_config(
        c.org,
        c.mission.mission_id,
        c.second.spacecraft_id
      )

    refute first_config.applied_binding_set_version == active.binding_set.version
    assert second_config.applied_binding_set_version == active.binding_set.version

    assert {:ok, %{review: %{state: "active"}}} =
             ConfigurationRead.load(
               c.scope,
               c.mission,
               c.first.spacecraft_id,
               "changes"
             )

    assert {:error, :spacecraft_configuration_review_required} =
             ConfigurationActivation.admit(%{
               organization_id: c.org,
               mission_id: c.mission.mission_id,
               metadata: %{}
             })

    assert {:error, :spacecraft_configuration_review_required} =
             Activations.record_binding_set_activation(
               c.mission.mission_id,
               active.binding_set.binding_set_id,
               active.binding_set.version,
               binding_set_content_sha256: activation.binding_set_content_sha256
             )

    assert {:error, :invalid_spacecraft_model_bindings} =
             ConfigurationActivation.admit(%{
               organization_id: nil,
               mission_id: c.mission.mission_id,
               metadata: activation.metadata
             })

    assert basis.source_runtime_bases[c.endpoint.source_endpoint_id].mission_model_revision_id ==
             c.revision.mission_model_revision_id

    assert basis.source_runtime_bases[c.other_endpoint.source_endpoint_id].mission_model_revision_id ==
             c.other_revision.mission_model_revision_id

    assert {:ok, commands} =
             Activations.with_locked_command_basis(c.org, c.mission.mission_id, fn locked ->
               SpacecraftModelBindings.command_basis(
                 locked,
                 c.other_endpoint.source_endpoint_id
               )
             end)

    assert commands.mission_model_revision_id == c.other_revision.mission_model_revision_id

    assert {:error, :spacecraft_model_not_active} =
             SpacecraftModelBindings.command_basis(activation, "unknown-source")
  end

  test "a changed saved draft cannot consume an earlier review", c do
    save(c, c.first, c.revision)
    assert {:ok, request} = review(c, c.first)
    save(c, c.first, c.other_revision)
    assert {:error, :spacecraft_configuration_changed} = activate(c, request)

    assert {:error, :no_active_binding_set} =
             Activations.fetch_active_activation(c.org, c.mission.mission_id)
  end

  test "competing activation reviews cannot restore an older fleet generation", c do
    save(c, c.first, c.revision)
    save(c, c.second, c.other_revision)
    assert {:ok, first_request} = review(c, c.first)
    assert {:ok, second_request} = review(c, c.second)
    assert {:ok, activation} = activate(c, first_request)
    assert {:error, :spacecraft_configuration_review_stale} = activate(c, second_request)
    assert {:ok, active} = Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert active.activation_id == activation.activation_id
    assert {:ok, repeated} = activate(c, first_request)
    assert repeated.activation_id == activation.activation_id
  end

  test "human approval applies each spacecraft model to the running mission", c do
    reviewer = Fixtures.user_scope(c.org, "approver")

    for {craft, revision} <- [{c.first, c.revision}, {c.second, c.other_revision}] do
      save(c, craft, revision)
      assert {:ok, request} = review(c, craft)

      assert {:ok, execution} =
               ControlActivations.approve_and_execute(
                 reviewer,
                 request.activation_request_id,
                 "Verified spacecraft configuration"
               )

      assert execution.status == :succeeded
    end

    assert {:ok, spec} = RuntimeMissions.applied_spec(c.mission.mission_id)
    assert spec.generation == 2

    assert spec.source_runtime_bases[c.endpoint.source_endpoint_id].mission_model_revision_id ==
             c.revision.mission_model_revision_id

    assert spec.source_runtime_bases[c.other_endpoint.source_endpoint_id].mission_model_revision_id ==
             c.other_revision.mission_model_revision_id
  end

  test "reviewed framing survives identity edits and cannot become another spacecraft's preset",
       c do
    protocol = %{
      "downlink" => "tm",
      "uplink" => "tc",
      "frame_size" => 1024,
      "secondary_header_length" => 0,
      "insert_zone_length" => 0,
      "ocf_length" => 0,
      "truncated_primary_header" => false
    }

    for selected_protocol <- [protocol, protocol, nil] do
      row = save(c, c.first, c.revision, %{"protocol" => selected_protocol})
      assert {:ok, request} = review(c, c.first)
      assert {:ok, _} = activate(c, request)

      {:ok, current} =
        SpacecraftStore.fetch_spacecraft(c.org, c.mission.mission_id, c.first.spacecraft_id)

      assert current.metadata["spacecraft_configuration_revision_id"] ==
               row.configuration_revision_id

      assert {:ok, pinned} = SpacecraftStore.fetch_pinned_profile(c.mission, current)
      assert ConfigurationInput.from_profile(pinned) == selected_protocol

      input = %{
        "spacecraft" => %{
          "display_name" => "Renamed vehicle",
          "scid" => "17",
          "spacecraft_type_id" => current.spacecraft_type_id,
          "spacecraft_type_version" => current.spacecraft_type_version
        }
      }

      assert {:ok, _} =
               Identity.action(
                 c.scope,
                 c.mission.mission_id,
                 current.spacecraft_id,
                 "save",
                 input
               )

      legacy_input = Map.update!(input, "spacecraft", &Map.delete(&1, "spacecraft_type_version"))

      assert {:ok, _} =
               Identity.action(
                 c.scope,
                 c.mission.mission_id,
                 current.spacecraft_id,
                 "validate",
                 legacy_input
               )

      replacement = %{
        "spacecraft_type_id" => if(pinned, do: nil, else: "unreviewed-preset"),
        "spacecraft_type_version" => if(pinned, do: nil, else: 1)
      }

      assert {:error, %{"spacecraft_type_id" => [message]}} =
               Identity.action(
                 c.scope,
                 c.mission.mission_id,
                 current.spacecraft_id,
                 "save",
                 Map.update!(input, "spacecraft", &Map.merge(&1, replacement))
               )

      assert message =~ "Communications"

      if pinned do
        assert {:error, %{"spacecraft_type_id" => [_]}} =
                 Identity.action(c.scope, c.mission.mission_id, nil, "save", input)
      end
    end
  end

  test "one operator activates an imported catalog without model approval or replay, using current settings",
       c do
    save(c, c.first, c.revision)
    policy = ActivationPolicy.load(c.org, c.mission.mission_id)

    assert {:ok, _} =
             ActivationPolicy.save(
               c.scope,
               c.mission.mission_id,
               policy.token,
               %{"value" => %{"approval_requirement" => "direct"}}
             )

    {:ok, page} = ConfigurationRead.load(c.scope, c.mission, c.first.spacecraft_id, "changes")

    assert {:error, :activation_policy_changed} =
             SpacecraftConfiguration.submit(
               c.scope,
               c.mission.mission_id,
               c.first.spacecraft_id,
               page.token,
               policy.token,
               :activate
             )

    assert {:ok, %{state: "active"}} =
             SpacecraftConfiguration.submit(
               c.scope,
               c.mission.mission_id,
               c.first.spacecraft_id,
               page.token,
               page.approval.token,
               :activate
             )

    assert {:ok, spec} = RuntimeMissions.applied_spec(c.mission.mission_id)

    assert spec.source_runtime_bases[c.endpoint.source_endpoint_id].mission_model_revision_id ==
             c.revision.mission_model_revision_id

    assert {:ok, %{status: :candidate}} =
             MissionModels.fetch_revision(
               c.org,
               c.mission.mission_id,
               c.revision.mission_model_revision_id
             )

    for schema <- [ComparisonReportRow, QualificationCaseRow] do
      refute Repo.exists?(
               from(row in schema,
                 where: row.organization_id == ^c.org and row.mission_id == ^c.mission.mission_id
               )
             )
    end
  end

  test "activation still requires the exact artifacts stored during import", c do
    save(c, c.first, c.revision)
    assert {:ok, request} = review(c, c.first)
    entry = request.metadata["spacecraft_configurations"][c.first.spacecraft_id]
    refute Map.has_key?(entry, "mission_model_comparison")
    assert :ok = SpacecraftModelBindings.validate(c.org, c.mission.mission_id, request.metadata)

    path = ["spacecraft_configurations", c.first.spacecraft_id, "mission_model"]

    wrong_revision =
      put_in(request.metadata, path ++ ["content_sha256"], String.duplicate("0", 64))

    assert {:error, {:mission_model_manifest_mismatch, :revision_content}} =
             SpacecraftModelBindings.validate(c.org, c.mission.mission_id, wrong_revision)

    wrong_plan =
      put_in(
        request.metadata,
        path ++ ["plans", "command", "content_sha256"],
        String.duplicate("0", 64)
      )

    assert {:error, :mission_model_runtime_plan_manifest_mismatch} =
             SpacecraftModelBindings.validate(c.org, c.mission.mission_id, wrong_plan)
  end

  test "the spacecraft review boundary rejects self review and applies a teammate's exact revision",
       c do
    save(c, c.first, c.revision)
    {:ok, page} = ConfigurationRead.load(c.scope, c.mission, c.first.spacecraft_id, "changes")

    assert {:ok, %{request_id: request_id}} =
             SpacecraftConfiguration.submit(
               c.scope,
               c.mission.mission_id,
               c.first.spacecraft_id,
               page.token,
               page.approval.token,
               :review
             )

    assert {:error, :activation_self_approval_forbidden} =
             SpacecraftConfiguration.decide(
               c.scope,
               c.mission.mission_id,
               c.first.spacecraft_id,
               page.token,
               request_id,
               "Reviewed",
               "approved"
             )

    assert {:ok, %{"outcome" => "applied"}} =
             SpacecraftConfiguration.decide(
               Fixtures.user_scope(c.org, "teammate"),
               c.mission.mission_id,
               c.first.spacecraft_id,
               page.token,
               request_id,
               "Verified spacecraft configuration",
               "approved"
             )

    assert {:ok, %{generation: 1}} = RuntimeMissions.applied_spec(c.mission.mission_id)
  end

  test "catalog list, database, revision, and spacecraft agree through saved and active transitions",
       c do
    assert_catalog_usage(c, c.revision, 0, 0)
    save(c, c.first, c.revision)
    assert_catalog_usage(c, c.revision, 0, 1)

    assert {:ok, request} = review(c, c.first)
    assert {:ok, _} = activate(c, request)
    assert_catalog_usage(c, c.revision, 1, 1)

    # A newer saved configuration does not replace the active catalog.
    save(c, c.first, c.other_revision)
    assert_catalog_usage(c, c.revision, 1, 0)
    assert_catalog_usage(c, c.other_revision, 0, 1)

    assert {:ok, page} =
             ConfigurationRead.load(c.scope, c.mission, c.first.spacecraft_id, "changes")

    assert page.active.document["catalog_revision_id"] == c.revision.catalog_revision_id
    assert page.document["catalog_revision_id"] == c.other_revision.catalog_revision_id

    assert {:ok, request} = review(c, c.first)
    assert {:ok, _} = activate(c, request)
    assert_catalog_usage(c, c.revision, 0, 0)
    assert_catalog_usage(c, c.other_revision, 1, 1)
  end

  test "database usage includes older revisions and counts each spacecraft once", c do
    save(c, c.first, c.revision)
    assert {:ok, request} = review(c, c.first)
    assert {:ok, _} = activate(c, request)

    {:ok, artifact} =
      Cadence.Catalog.fetch_artifact(c.org, c.mission.mission_id, c.revision.artifact_id)

    {:ok, run} =
      Cadence.Catalog.start_revision_import(
        c.org,
        c.mission.mission_id,
        c.revision.catalog_database_id,
        artifact,
        "cadence_yaml",
        metadata: %{"revision_label" => "Next imported revision"}
      )

    {:ok, _} = Cadence.Catalog.execute_enqueued_run(run.import_run_id)

    {:ok, next} =
      Cadence.Catalog.fetch_revision_by_import_run(c.org, c.mission.mission_id, run.import_run_id)

    assert_catalog_usage(c, c.revision, 1, 1)
    save(c, c.first, next)

    {:ok, database} =
      Databases.catalog_database_show(
        c.org,
        c.mission.mission_id,
        %{"catalog_database_id" => c.revision.catalog_database_id}
      )

    assert database["database"]["spacecraft_usage"] == %{active_count: 1, saved_count: 1}
    rows = Map.new(database["revisions"], &{&1["revision_id"], &1["spacecraft_usage"]})
    assert rows[c.revision.catalog_revision_id] == %{active_count: 1, saved_count: 0}
    assert rows[next.catalog_revision_id] == %{active_count: 0, saved_count: 1}

    {:ok, index} = Databases.catalog_index(c.org, c.mission.mission_id)

    row =
      Enum.find(
        index["presentation"]["card"]["rows"],
        &String.ends_with?(&1["href"], c.revision.catalog_database_id)
      )

    assert row["spacecraft_usage"] == %{active_count: 1, saved_count: 1}
    assert row["latest_revision"]["label"] == "Next imported revision"
  end

  defp assert_catalog_usage(c, revision, active, saved) do
    summary = %{active_count: active, saved_count: saved}
    {:ok, index} = Databases.catalog_index(c.org, c.mission.mission_id)

    row =
      Enum.find(
        index["presentation"]["card"]["rows"],
        &String.ends_with?(&1["href"], revision.catalog_database_id)
      )

    assert row["spacecraft_usage"] == summary

    {:ok, database} =
      Databases.catalog_database_show(c.org, c.mission.mission_id, %{
        "catalog_database_id" => revision.catalog_database_id
      })

    assert database["database"]["spacecraft_usage"] == summary
    row = Enum.find(database["revisions"], &(&1["revision_id"] == revision.catalog_revision_id))
    assert row["spacecraft_usage"] == summary

    {:ok, detail} =
      Revisions.catalog_revision_show(c.org, c.mission.mission_id, %{
        "catalog_revision_id" => revision.catalog_revision_id
      })

    usage = detail["spacecraft_usage"]
    assert Enum.count(usage.usage, & &1.active) == active
    assert Enum.count(usage.usage, & &1.saved) == saved
    assert usage.total_count == length(usage.usage)

    for row <- usage.usage do
      assert row.href == "/missions/#{c.mission.mission_id}/spacecraft/#{row.id}?section=changes"
    end
  end

  defp save(c, spacecraft, revision, overrides \\ %{}) do
    {:ok, spacecraft} =
      SpacecraftStore.fetch_spacecraft(c.org, c.mission.mission_id, spacecraft.spacecraft_id)

    snapshot = ConfigurationDrafts.snapshot(c.mission, spacecraft)

    document = %{
      ConfigurationInput.empty()
      | "catalog_revision_id" => revision.catalog_revision_id,
        "commanding_enabled" => true,
        "telemetry_enabled" => true,
        "handled_apids" => [42]
    }

    assert {:ok, row} =
             ConfigurationDrafts.save(
               c.scope,
               c.mission.mission_id,
               spacecraft.spacecraft_id,
               snapshot.token,
               Map.merge(document, overrides)
             )

    row
  end

  defp review(c, spacecraft) do
    {:ok, spacecraft} =
      SpacecraftStore.fetch_spacecraft(c.org, c.mission.mission_id, spacecraft.spacecraft_id)

    ConfigurationReview.request(
      c.scope,
      c.mission.mission_id,
      spacecraft.spacecraft_id,
      ConfigurationDrafts.snapshot(c.mission, spacecraft).token
    )
  end

  defp activate(c, request) do
    {:ok, current} = ManagementActivations.fetch(c.scope, request.activation_request_id)

    if current.state == :approval_pending do
      assert {:ok, _, _, _} =
               ManagementActivations.approve(
                 Fixtures.user_scope(c.org, "fixture-reviewer"),
                 request.activation_request_id,
                 "Reviewed exact fixture configuration"
               )
    end

    {:ok, binding_set} =
      Governance.fetch_binding_set(
        c.org,
        c.mission.mission_id,
        request.binding_set_id,
        request.binding_set_version
      )

    assert :ok =
             MissionModelPromotion.validate_activation_metadata(
               c.org,
               c.mission.mission_id,
               binding_set,
               request.metadata
             )

    Activations.record_binding_set_activation(
      c.org,
      c.mission.mission_id,
      request.binding_set_id,
      request.binding_set_version,
      activation_request_id: request.activation_request_id,
      metadata: request.metadata,
      binding_set_content_sha256: MissionRuntimeSpec.content_sha256(binding_set)
    )
  end
end
