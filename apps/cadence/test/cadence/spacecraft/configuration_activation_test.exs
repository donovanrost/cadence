defmodule Cadence.Activations.SpacecraftConfigurationTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Activations.SpacecraftConfiguration, as: ConfigurationActivation
  alias Cadence.Applications.{ActionRequest, HostContext, TelemetryDecom}
  alias Cadence.Applications.TelemetryDecom.ActionProvider, as: DecomActions
  alias Cadence.Catalog.FleetSnapshot
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.SpacecraftConfiguration
  alias Cadence.Control.ModelApprovalGate
  alias Cadence.Control.SpacecraftModelBindings
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.MissionModelApproval
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{ComparisonReportRow, QualificationCaseRow, RevisionRow}
  alias Cadence.Platform.ContentHash
  alias Cadence.Reads.Catalog.{Databases, Revisions}
  alias Cadence.Reads.Spacecraft.Configuration, as: ConfigurationRead
  alias Cadence.Runtime.MissionRuntimeSpec
  alias Cadence.Runtime.Missions, as: RuntimeMissions
  alias Cadence.Runtime.PartitionKey
  alias Cadence.Runtime.SourceRuntimeBases
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

    # Preserve the persisted identity from the former source-to-full-model representation.
    source_hashes =
      Enum.map(basis.source_runtime_bases, fn {source, model} ->
        {source,
         MissionRuntimeSpec.runtime_basis_sha256(spec.binding_set_content_sha256, %{
           revision_id: model.mission_model_revision_id,
           content_sha256: model.mission_model_content_sha256,
           plans: model.runtime_plans
         })}
      end)

    assert spec.runtime_basis_sha256 ==
             ContentHash.term_sha256(
               {:spacecraft_models_v1, spec.binding_set_content_sha256, Enum.sort(source_hashes)}
             )

    assert {:ok, ^spec} = MissionRuntimeSpec.new(Map.from_struct(spec))

    [key | _] = Map.keys(spec.source_runtime_bases.models)
    broken = put_in(spec.source_runtime_bases.models[key].runtime_plans, %{})

    assert {:error, {:invalid_mission_runtime_spec, :source_runtime_bases}} =
             MissionRuntimeSpec.new(Map.from_struct(broken))

    for {endpoint, revision} <- [{c.endpoint, c.revision}, {c.other_endpoint, c.other_revision}] do
      assert {:ok, partition} =
               MissionRuntimeSpec.partition_input(
                 spec,
                 %PartitionKey{
                   affinity: :source_endpoint,
                   value: endpoint.source_endpoint_id
                 }
               )

      assert partition.mission_model_revision_id == revision.mission_model_revision_id
      assert Map.keys(partition.source_runtime_bases.sources) == [endpoint.source_endpoint_id]
      assert map_size(partition.source_runtime_bases.models) == 1
      assert MissionRuntimeSpec.identity(partition) == MissionRuntimeSpec.identity(spec)

      assert Enum.all?(partition.binding_set.capability_instances, fn instance ->
               instance.target_scope == :mission or
                 instance.source_endpoint_ref == endpoint.source_endpoint_id
             end)

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

    # The control plane hands TelemetryDecom the admitted entries (it can't read stored fleets).
    {:ok, entries} = FleetSnapshot.entries(activation.metadata)

    assert :ok =
             TelemetryDecom.activation_applied(
               active.binding_set,
               %{"spacecraft_configuration_version" => 1, "spacecraft_configurations" => entries}
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

    # Sweep row 6 (rule (b)): the direct host writes are refused server-side too, before review,
    # and write nothing; only request_activation was gated before.
    host = HostContext.spacecraft(c.mission.mission_id, c.first.spacecraft_id)

    {:ok, before} =
      TelemetryDecom.fetch_config(c.org, c.mission.mission_id, c.first.spacecraft_id)

    for {surface, action} <- [
          {"manage", "save_configuration"},
          {"manage", "disable"},
          {"packet_bindings", "save_packet_bindings"}
        ] do
      request = %ActionRequest{
        application_key: "telemetry_decom",
        application_version: 1,
        surface_id: surface,
        surface_version: 1,
        action_id: action,
        params: %{}
      }

      assert {:error, :spacecraft_configuration_review_required} =
               DecomActions.execute(c.scope, host, request),
             action
    end

    assert {:ok, ^before} =
             TelemetryDecom.fetch_config(c.org, c.mission.mission_id, c.first.spacecraft_id)

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

    assert source_model(spec, c.endpoint.source_endpoint_id).mission_model_revision_id ==
             c.revision.mission_model_revision_id

    assert source_model(spec, c.other_endpoint.source_endpoint_id).mission_model_revision_id ==
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
                 "validate",
                 input
               )

      # Host-action sweep row 2: a save is refused (the console's change sets edit spacecraft);
      # the governed-pin rule below is checked through validate, which still applies it.
      assert {:error, %{"display_name" => [refused]}} =
               Identity.action(
                 c.scope,
                 c.mission.mission_id,
                 current.spacecraft_id,
                 "save",
                 input
               )

      assert refused =~ "Setup › Spacecraft"

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
                 "validate",
                 Map.update!(input, "spacecraft", &Map.merge(&1, replacement))
               )

      assert message =~ "Communications"

      if pinned do
        assert {:error, %{"spacecraft_type_id" => [_]}} =
                 Identity.action(c.scope, c.mission.mission_id, nil, "validate", input)
      end
    end
  end

  # Under DECISIONS #92 a the property is: with the `direct` activation policy, ONE operator's
  # single submit activates a spacecraft onto an imported catalog whose model is approved: no
  # separate approval step, no qualification, no replay, the current settings. An imported model
  # that isn't approved is refused on this path (the next test), not activated.
  test "one operator activates an approved imported catalog directly: no separate approval step, qualification or replay",
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

    # Before the submit: the model is approved by the fixture, and the baseline #92 a compares it
    # against is the revision this spacecraft runs in the active generation (nil with none).
    model_id = c.revision.mission_model_revision_id
    approval = fn -> model_approval(c, model_id) end
    approved_before = approval.()
    assert approved_before.status == "approved"
    baseline = running_model(c, c.first.spacecraft_id)

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

    assert source_model(spec, c.endpoint.source_endpoint_id).mission_model_revision_id ==
             c.revision.mission_model_revision_id

    # The activation approved nothing (the approval is the fixture's, unchanged) and the gate
    # ran its one comparison of the introduced model against the baseline; no qualification.
    assert approval.() == approved_before

    scoped = fn schema ->
      from(row in schema,
        where: row.organization_id == ^c.org and row.mission_id == ^c.mission.mission_id
      )
    end

    assert [report] = Repo.all(scoped.(ComparisonReportRow))
    assert report.status == :passed
    assert report.candidate_revision_id == model_id
    assert report.baseline_revision_id == baseline
    refute Repo.exists?(scoped.(QualificationCaseRow))
  end

  test "the same direct activation onto an imported catalog whose model isn't approved is held, not activated",
       c do
    unapproved =
      Fixtures.persist_imported_revision!(c.org, c.mission.mission_id,
        revision_label: "Unapproved",
        approve: false
      )

    save(c, c.first, unapproved)
    policy = ActivationPolicy.load(c.org, c.mission.mission_id)

    assert {:ok, _} =
             ActivationPolicy.save(
               c.scope,
               c.mission.mission_id,
               policy.token,
               %{"value" => %{"approval_requirement" => "direct"}}
             )

    {:ok, page} = ConfigurationRead.load(c.scope, c.mission, c.first.spacecraft_id, "changes")
    model_id = unapproved.mission_model_revision_id

    # #92 a's gate refuses the generation (mission_model_revision_not_approved); the direct
    # path reports any execution refusal as needing review, and nothing is activated.
    assert ModelApprovalGate.unapproved(c.org, c.mission.mission_id, [model_id]) == [model_id]
    assert {:ok, %{"outcome" => "application_needs_review"}} = submit_direct(c, page)
    refute running_on?(c, model_id)

    MissionModelApproval.approve!(c.org, c.mission.mission_id, model_id)
    {:ok, page} = ConfigurationRead.load(c.scope, c.mission, c.first.spacecraft_id, "changes")
    assert {:ok, %{state: "active"}} = submit_direct(c, page)
    assert running_on?(c, model_id)
  end

  test "activation still requires the exact artifacts stored during import", c do
    save(c, c.first, c.revision)
    assert {:ok, request} = review(c, c.first)
    assert {:ok, entry} = FleetSnapshot.entry(request.metadata, c.first.spacecraft_id)
    refute Map.has_key?(entry, "mission_model_comparison")
    assert :ok = SpacecraftModelBindings.validate(c.org, c.mission.mission_id, request.metadata)

    # Tamper with the entries in their inline (v1) form; validation applies to both forms.
    {:ok, entries} = FleetSnapshot.entries(request.metadata)
    inline = %{"spacecraft_configuration_version" => 1, "spacecraft_configurations" => entries}
    path = ["spacecraft_configurations", c.first.spacecraft_id, "mission_model"]

    wrong_revision = put_in(inline, path ++ ["content_sha256"], String.duplicate("0", 64))

    assert {:error, {:mission_model_manifest_mismatch, :revision_content}} =
             SpacecraftModelBindings.validate(c.org, c.mission.mission_id, wrong_revision)

    wrong_plan =
      put_in(
        inline,
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

  defp model_approval(c, model_id) do
    RevisionRow
    |> Repo.get_by!(mission_id: c.mission.mission_id, revision_id: model_id)
    |> Map.take([:status, :approved_at, :approved_by])
  end

  # The revision #92 a's gate treats as a spacecraft's baseline: the one it runs in the active
  # generation (a legacy activation's mission-wide entry counts for every spacecraft), else nil.
  defp running_model(c, spacecraft_id) do
    running = ModelApprovalGate.running_entries(c.org, c.mission.mission_id)

    case running[spacecraft_id] || running["__mission__"] do
      %{"mission_model" => %{"revision_id" => id}} -> id
      _none -> nil
    end
  end

  # Whether the first spacecraft's source runs `model_id` in the applied generation.
  defp running_on?(c, model_id) do
    case RuntimeMissions.applied_spec(c.mission.mission_id) do
      {:ok, spec} ->
        case source_model(spec, c.endpoint.source_endpoint_id) do
          %{mission_model_revision_id: ^model_id} -> true
          _other -> false
        end

      _none ->
        false
    end
  end

  defp submit_direct(c, page) do
    SpacecraftConfiguration.submit(
      c.scope,
      c.mission.mission_id,
      c.first.spacecraft_id,
      page.token,
      page.approval.token,
      :activate
    )
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

  defp source_model(spec, source) do
    {:ok, basis} = SourceRuntimeBases.fetch(spec.source_runtime_bases, source)
    basis
  end
end
