defmodule Cadence.Configuration.CatalogGenerationTest do
  @moduledoc "Catalog-path generations (DECISIONS #36/#65)."
  use Cadence.RuntimeCase, async: false

  alias Cadence.Activations.GenerationReceipts
  alias Cadence.Applications.{ApplicationInstallations, HostContext, PacketBindings}

  alias Cadence.Applications.SpacecraftConfiguration.{
    Assignments,
    CatalogAuthority,
    Drafts,
    Review
  }

  alias Cadence.Applications.TelemetryDecom
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.{CompositionPins, FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.{Configuration, ConfigurationRollback, ModelApprovalGate}
  alias Cadence.Control.MissionRuntime, as: ControlMissionRuntime
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.MissionModelApproval
  alias Cadence.MissionModels.TelemetryProjection
  alias Cadence.Runtime.{MissionCoordinator, MissionModelPlanDecoder, MissionRuntimeSpec}
  alias Cadence.Telemetry.PacketDefinition

  setup do
    org = "org-catalog-gen-#{System.unique_integer([:positive])}"
    mid = "mission-catalog-gen-#{System.unique_integer([:positive])}"
    {craft, revision, endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    configure(scope, mission, craft, revision.catalog_revision_id)
    rev2 = Fixtures.persist_imported_revision!(org, mid, revision_label: "Rev 2")

    %{
      org: org,
      mission: mission,
      scope: scope,
      craft: craft,
      endpoint: endpoint,
      rev1: revision.catalog_revision_id,
      rev2: rev2.catalog_revision_id
    }
  end

  test "a profile catalog change set moves its pinned spacecraft onto the new catalog in one generation",
       c do
    profile = profile!(c, c.rev1)
    {:ok, before} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    {:ok, staged} =
      stage(c, [update("spacecraft_profile", profile, "composition_id", pin!(c, c.rev2))])

    assert {:ok, %{verdict: :hold, checks: checks}} =
             Configuration.preview(
               c.scope,
               c.mission.mission_id,
               staged.change_set_id
             )

    assert %{items: items, blocking: false} = Enum.find(checks, &(&1.key == "compatibility"))

    assert %{sentence: sentence} =
             Enum.find(items, &(&1.reason == :catalog_change and &1.to == c.rev2))

    assert sentence =~ ~r/with catalog rev \d+ instead of rev \d+\./

    assert {:ok, %{state: :applied, generation: generation, revision: revision}} =
             submit(c, staged)

    assert generation > before.generation

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)
    assert entry["catalog_revision_id"] == c.rev2

    # 2026-11-12: the generation's hash is the persisted binding set's, so a restart can
    # re-admit it (the in-memory build carries field ids the store doesn't keep).
    assert {:ok, persisted} =
             Cadence.Governance.fetch_binding_set(
               c.org,
               c.mission.mission_id,
               active.binding_set_id,
               active.binding_set_version
             )

    assert active.binding_set_content_sha256 == MissionRuntimeSpec.content_sha256(persisted)

    assert {^active, %DateTime{} = applied_at} =
             GenerationReceipts.latest(c.org, c.mission.mission_id)

    assert :ok = GenerationReceipts.record(active, DateTime.add(applied_at, 1, :second))
    assert {^active, ^applied_at} = GenerationReceipts.latest(c.org, c.mission.mission_id)

    assert {:error, :spacecraft_configuration_review_stale} =
             GenerationReceipts.record(before, DateTime.utc_now())

    assert_readmitted(c)

    latest = Drafts.latest(c.org, c.mission.mission_id, c.craft.spacecraft_id)
    assert latest.catalog_revision_id == c.rev2
    assert latest.composition_id == pin!(c, c.rev2)
    assert latest.effective_revision_id == entry["mission_model"]["revision_id"]
    assert latest.change_set_id == staged.change_set_id
    assert latest.change_set_revision == revision
    assert latest.configuration_revision_id == entry["configuration_revision_id"]
    assert CatalogAuthority.mismatches(c.org, c.mission.mission_id) == []
    assert_projected(c, c.rev2)

    # Rolling it back goes the same way.
    {:ok, rollback} = ConfigurationRollback.stage(c.scope, c.mission.mission_id, revision - 1)
    assert {:ok, %{state: :applied}} = submit(c, rollback)

    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    assert {:ok, %{"catalog_revision_id" => rev1}} =
             FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)

    assert rev1 == c.rev1
    assert_projected(c, c.rev1)
  end

  test "a custom endpoint is pinned on a draft without changing the running assignment", c do
    endpoint =
      Fixtures.persist_source_endpoint!(c.org, c.mission.mission_id, c.craft.spacecraft_id,
        display_name: "Alternate"
      )

    active = Drafts.latest(c.org, c.mission.mission_id, c.craft.spacecraft_id)
    current = Drafts.snapshot(c.mission, c.craft)

    document =
      Map.put(current.document, "telemetry_source_endpoint_id", endpoint.source_endpoint_id)

    assert {:ok, assignment} =
             Drafts.save(
               c.scope,
               c.mission.mission_id,
               c.craft.spacecraft_id,
               current.token,
               document
             )

    assert assignment.artifact_sha256 == active.artifact_sha256
    assert assignment.version == active.version + 1

    assert {:ok, %{document: ^document}} =
             Drafts.fetch(c.org, c.mission.mission_id, assignment.configuration_revision_id)

    assert {:ok, running} =
             Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)

    assert {:ok, entry} = FleetSnapshot.entry(running.metadata, c.craft.spacecraft_id)
    assert entry["configuration_revision_id"] == active.configuration_revision_id
    assert entry["document"]["telemetry_source_endpoint_id"] == c.endpoint.source_endpoint_id

    assert {:ok, %{source_endpoint_id: source, applied_generation: nil, applied_at: nil}} =
             TelemetryDecom.fetch_config(c.org, c.mission.mission_id, c.craft.spacecraft_id)

    assert source == endpoint.source_endpoint_id

    assert {:error, :spacecraft_configuration_not_found} =
             Drafts.fetch(
               "another-org",
               c.mission.mission_id,
               assignment.configuration_revision_id
             )
  end

  test "the database refuses to update, delete, or truncate configuration evidence", c do
    assignment = Drafts.latest(c.org, c.mission.mission_id, c.craft.spacecraft_id)

    assert_append_only(
      "spacecraft_configuration_assignments",
      "configuration_revision_id",
      assignment.configuration_revision_id
    )

    assert_append_only(
      "spacecraft_configuration_artifacts",
      "sha256",
      assignment.artifact_sha256
    )
  end

  defp assert_append_only(table, key, value) do
    for {operation, sql, params} <- [
          {"UPDATE", "UPDATE #{table} SET #{key} = #{key} WHERE #{key} = $1", [value]},
          {"DELETE", "DELETE FROM #{table} WHERE #{key} = $1", [value]},
          {"TRUNCATE", "TRUNCATE #{table} CASCADE", []}
        ] do
      assert {:error, %Postgrex.Error{postgres: %{code: :raise_exception, message: message}}} =
               Repo.query(sql, params, mode: :savepoint)

      assert message == "decision records are append-only: #{operation} on #{table} refused"
    end
  end

  test "a new draft round-trips an explicit nil source without taking a spacecraft endpoint", c do
    craft =
      Fixtures.persist_spacecraft!(c.org, c.mission.mission_id, display_name: "Unconfigured")

    current = Drafts.snapshot(c.mission, craft)
    document = SpacecraftConfigurationInput.empty()

    assert {:ok, %{version: 1} = assignment} =
             Drafts.save(
               c.scope,
               c.mission.mission_id,
               craft.spacecraft_id,
               current.token,
               document
             )

    assert {:ok, %{document: ^document, source_endpoint_id: nil}} =
             Drafts.fetch(c.org, c.mission.mission_id, assignment.configuration_revision_id)
  end

  # 11-15 (001 on dev): a change-set move left the stored decom config on the old catalog. The
  # decom and packet-input surfaces read it, and Drafts.snapshot overlaid it on the document once
  # the application basis changed, so the next Save reverted the move.
  test "a later application change doesn't revert a change-set catalog move", c do
    profile = profile!(c, c.rev1)
    apply!(c, [update("spacecraft_profile", profile, "composition_id", pin!(c, c.rev2))])

    host = HostContext.spacecraft(c.mission.mission_id, c.craft.spacecraft_id)
    assert {:ok, _} = ApplicationInstallations.disable(c.scope, host, "telemetry_decom")

    snapshot = Drafts.snapshot(c.mission, c.craft)
    assert snapshot.external_changes
    assert snapshot.document["handled_apids"] == [42]
    assert snapshot.document["catalog_revision_id"] == c.rev2
  end

  # 11-15: Save re-points a spacecraft's packet inputs at its new catalog; a change-set move left
  # them on the old one. The apply now does it from the catalog it already loaded.
  test "a change-set catalog move re-points the spacecraft's packet inputs", c do
    host = HostContext.spacecraft(c.mission.mission_id, c.craft.spacecraft_id)

    {:ok, installation} =
      ApplicationInstallations.fetch_installed(c.scope, host, "telemetry_decom")

    {:ok, config} =
      TelemetryDecom.fetch_config(c.org, c.mission.mission_id, c.craft.spacecraft_id)

    assert {:ok, input} =
             PacketBindings.replace(c.scope, host, installation.application_installation_id, %{
               input_id: "telemetry-fields",
               input_version: 1,
               catalog_revision_id: c.rev1,
               source_endpoint_ref: config.source_endpoint_id,
               selected_packet_ids: packet_ids(c, c.rev1, [42])
             })

    profile = profile!(c, c.rev1)
    apply!(c, [update("spacecraft_profile", profile, "composition_id", pin!(c, c.rev2))])

    assert [moved] =
             PacketBindings.list_for_mission(c.org, c.mission.mission_id,
               application_key: "telemetry_decom",
               spacecraft_ids: [c.craft.spacecraft_id]
             )

    assert moved.configuration_version == input.configuration_version + 1
    assert Enum.map(moved.bindings, & &1.catalog_revision_id) == [c.rev2]
    assert Enum.map(moved.bindings, & &1.apid) == [42]
    # Its basis moved with it, and the revision was stamped with the new one.
    refute Drafts.snapshot(c.mission, c.craft).external_changes
  end

  defp packet_ids(c, catalog_id, apids) do
    {:ok, revision} = Cadence.Catalog.fetch_revision(c.org, c.mission.mission_id, catalog_id)
    {:ok, telemetry} = TelemetryProjection.load(c.org, c.mission.mission_id, revision)
    for p <- telemetry.packet_definitions, p.apid in apids, do: p.packet_definition_id
  end

  defp assert_projected(c, catalog) do
    assert {:ok, config} =
             TelemetryDecom.fetch_config(c.org, c.mission.mission_id, c.craft.spacecraft_id)

    assert config.catalog_revision_id == catalog

    snapshot = Drafts.snapshot(c.mission, c.craft)
    refute snapshot.external_changes
    assert snapshot.document["catalog_revision_id"] == catalog
  end

  # DECISIONS #92 (a): the change-set path introduced model revisions without approval.
  test "a change set can't move spacecraft onto a mission model nobody approved", c do
    rev3 =
      Fixtures.persist_imported_revision!(c.org, c.mission.mission_id,
        revision_label: "Rev 3",
        approve: false
      )

    profile = profile!(c, c.rev1)

    {:ok, staged} =
      stage(c, [
        update("spacecraft_profile", profile, "composition_id", pin!(c, rev3.catalog_revision_id))
      ])

    # D3 (#544; design §3): the profile pins rev 3's composition,
    # which has no approved revision, so it's a validation NO-GO on the pin (no longer only the
    # blocking HOLD, which a NO-GO's preview doesn't reach).
    assert {:ok, %{verdict: :no_go, checks: checks}} =
             Configuration.preview(c.scope, c.mission.mission_id, staged.change_set_id)

    assert %{items: [%{errors: [%{path: "composition_id", message: message}]}]} =
             Enum.find(checks, &(&1.key == "validation"))

    assert message =~ "isn't approved"

    # The default baseline for its approval: no earlier import in its database, so the revision
    # the fleet runs now.
    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)

    assert ModelApprovalGate.default_baseline(
             c.org,
             c.mission.mission_id,
             rev3.mission_model_revision_id
           ) ==
             entry["mission_model"]["revision_id"]

    assert {:error, _not_go} = submit(c, staged)

    MissionModelApproval.approve!(c.org, c.mission.mission_id, rev3.mission_model_revision_id)
    assert {:ok, %{state: :applied}} = submit(c, staged)
  end

  test "the per-spacecraft review can't introduce a mission model nobody approved", c do
    rev3 =
      Fixtures.persist_imported_revision!(c.org, c.mission.mission_id,
        revision_label: "Rev 3",
        approve: false
      )

    result = try_configure(c.scope, c.mission, c.craft, rev3.catalog_revision_id)
    assert {:error, {:mission_model_revision_not_approved, [id]}} = result
    assert id == rev3.mission_model_revision_id

    MissionModelApproval.approve!(c.org, c.mission.mission_id, id)

    assert {:ok, %{status: :succeeded}} =
             try_configure(c.scope, c.mission, c.craft, rev3.catalog_revision_id)
  end

  test "an approval's default baseline is the database's previous model, skipping imports without one",
       c do
    {:ok, rev1} = Cadence.Catalog.fetch_revision(c.org, c.mission.mission_id, c.rev1)
    db = rev1.catalog_database_id

    middle =
      Fixtures.persist_imported_revision!(c.org, c.mission.mission_id,
        catalog_database_id: db,
        revision_label: "Rev 2b",
        yaml: yaml_with_apid(43)
      )

    latest =
      Fixtures.persist_imported_revision!(c.org, c.mission.mission_id,
        catalog_database_id: db,
        revision_label: "Rev 3b",
        yaml: yaml_with_apid(44)
      )

    assert ModelApprovalGate.default_baseline(
             c.org,
             c.mission.mission_id,
             latest.mission_model_revision_id
           ) ==
             middle.mission_model_revision_id

    # An import in between that produced no model is skipped.
    Repo.query!(
      "UPDATE catalog_revisions SET mission_model_revision_id = NULL WHERE catalog_revision_id = $1",
      [
        middle.catalog_revision_id
      ]
    )

    # (The catalog's own answer: the fleet fallback would also give rev 1's model here.)
    assert Cadence.Catalog.previous_model_revision(
             c.org,
             c.mission.mission_id,
             latest.mission_model_revision_id
           ) == rev1.mission_model_revision_id
  end

  test "a running model nobody approved is grandfathered: other changes still apply", c do
    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    {:ok, entry} = FleetSnapshot.entry(active.metadata, c.craft.spacecraft_id)
    running = entry["mission_model"]["revision_id"]

    Repo.query!(
      "UPDATE mission_model_revisions SET status = 'candidate' WHERE revision_id = $1",
      [running]
    )

    assert ModelApprovalGate.running?(c.org, c.mission.mission_id, running)

    # The gate would refuse it if a generation introduced it...
    assert ModelApprovalGate.unapproved(c.org, c.mission.mission_id, [running]) == [running]

    # ...but it's running, so a change set that keeps the spacecraft on it still applies.
    assert {:ok, %{state: :applied}} =
             apply!(c, [switch(c.craft.spacecraft_id, "commanding_enabled", false)])
  end

  test "waiting commands are canceled with catalog_changed; a command in flight blocks the apply",
       c do
    profile = profile!(c, c.rev1)
    waiting = request!(c, "validated")
    in_flight = request!(c, "released", verification_state: "pending")

    {:ok, staged} =
      stage(c, [update("spacecraft_profile", profile, "composition_id", pin!(c, c.rev2))])

    assert {:ok, %{checks: checks}} =
             Configuration.preview(
               c.scope,
               c.mission.mission_id,
               staged.change_set_id
             )

    assert %{items: items, blocking: true} = Enum.find(checks, &(&1.key == "compatibility"))
    reasons = MapSet.new(items, & &1.reason)
    assert :catalog_cancels_commands in reasons and :catalog_command_in_flight in reasons

    assert {:error, {:holds_blocking, _preview}} = submit(c, staged)

    # The command finishes; now the apply goes through and cancels the waiting one.
    Repo.query!(
      "UPDATE command_requests SET verification_state = 'satisfied' WHERE command_request_id = $1",
      [
        in_flight
      ]
    )

    assert {:ok, %{state: :applied}} = submit(c, staged)

    %{rows: [[state, metadata]]} =
      Repo.query!(
        "SELECT lifecycle_state, metadata_document FROM command_requests WHERE command_request_id = $1",
        [waiting]
      )

    assert state == "canceled"
    assert get_in(metadata, ["value", "cancellation", "reason"]) =~ "catalog_changed: "
  end

  test "a profile catalog has one writer: the spacecraft's own configuration can't diverge, and divergence is listed",
       c do
    # Simulate a profile pin ahead of the running configuration, without deriving a new head.
    pin_without_generation!(c)

    assert [
             %{
               spacecraft_id: id,
               effective_catalog_revision_id: rev2,
               configured_catalog_revision_id: rev1
             }
           ] =
             CatalogAuthority.mismatches(c.org, c.mission.mission_id)

    assert {id, rev2, rev1} == {c.craft.spacecraft_id, c.rev2, c.rev1}

    current = Drafts.snapshot(c.mission, c.craft)

    assert {:error, :spacecraft_catalog_set_by_profile} =
             Drafts.save(
               c.scope,
               c.mission.mission_id,
               c.craft.spacecraft_id,
               current.token,
               Map.put(current.document, "catalog_revision_id", c.rev1)
             )
  end

  # qa #43: a fleet with more configured spacecraft than SpacecraftStore reads in one batch
  # crashed the mismatch read, and with it the console's Readiness.
  test "mismatches read a fleet larger than one spacecraft batch", c do
    pin_without_generation!(c)
    latest = Drafts.latest(c.org, c.mission.mission_id, c.craft.spacecraft_id)

    clones = Cadence.SpacecraftStore.max_batch_size()

    Repo.query!(
      "INSERT INTO mission_spacecraft (spacecraft_id, organization_id, mission_id, display_name, " <>
        "metadata, inserted_at, scid, spacecraft_type_id, spacecraft_type_version, lifecycle_state) " <>
        "SELECT spacecraft_id || '-clone-' || n, organization_id, mission_id, " <>
        "display_name || ' ' || n, metadata, inserted_at, NULL, spacecraft_type_id, " <>
        "spacecraft_type_version, lifecycle_state " <>
        "FROM mission_spacecraft, generate_series(1, $2) AS n WHERE spacecraft_id = $1",
      [c.craft.spacecraft_id, clones]
    )

    1..clones
    |> Enum.map(fn n ->
      row =
        Assignments.new(
          c.mission,
          "#{c.craft.spacecraft_id}-clone-#{n}",
          1,
          latest.document,
          latest.created_by,
          Map.take(latest, [:composition_id, :effective_revision_id])
        )

      %{row | application_basis: latest.application_basis}
    end)
    |> Assignments.append()

    mismatches = CatalogAuthority.mismatches(c.org, c.mission.mission_id)

    assert length(mismatches) == clones + 1

    assert Enum.all?(
             mismatches,
             &(&1.effective_catalog_revision_id == c.rev2 and
                 &1.configured_catalog_revision_id == c.rev1)
           )
  end

  ## Helpers

  # As after a restart: the reconciler rebuilds the generation from the store, and a sample
  # still reaches the semantic runtime with its parameter id (from the mission-model plan).
  defp assert_readmitted(c) do
    reconciler = ControlMissionRuntime.reconciler_name(c.mission.mission_id)
    old = GenServer.whereis(reconciler)
    Process.exit(old, :kill)

    assert_eventually(fn ->
      pid = GenServer.whereis(reconciler)

      pid not in [nil, old] and
        match?(
          %{applied_generation: g, last_error: nil} when is_integer(g),
          GenServer.call(pid, :snapshot)
        )
    end)

    assert {:ok, spec} = MissionCoordinator.active_spec(c.mission.mission_id)
    {:ok, active} = Cadence.Activations.fetch_active_activation(c.org, c.mission.mission_id)
    assert spec.generation == active.generation

    # Re-read, the binding set's packet fields carry their parameter ids (#73: stored on the field
    # rows, left out of the content hash). Each still resolves, as PartitionOwner does, to the
    # mission-model plan's definition, with the same ids. That is what gives samples their
    # semantic_id and so a semantic Update.
    telemetry =
      for %{runtime_configuration: %PacketDefinition{} = configured} <-
            spec.binding_set.capability_instances,
          do: configured

    assert telemetry != []

    assert Enum.all?(telemetry, fn configured ->
             Enum.all?(configured.fields, &is_binary(&1.parameter_id))
           end)

    assert {:ok, definitions} =
             MissionModelPlanDecoder.telemetry_packet_definitions(spec.runtime_plans)

    for configured <- telemetry do
      resolved =
        Enum.find(definitions, &(&1.packet_definition_id == configured.packet_definition_id))

      assert resolved

      assert Enum.map(resolved.fields, & &1.parameter_id) ==
               Enum.map(configured.fields, & &1.parameter_id)
    end
  end

  defp assert_eventually(fun, attempts \\ 100)
  defp assert_eventually(_fun, 0), do: flunk("condition was not satisfied in time")

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp pin_without_generation!(c) do
    profile = profile!(c, c.rev2)

    # Put the craft back on the earlier artifact without changing what the profile pins.
    [latest, earlier | _] = Drafts.history(c.org, c.mission.mission_id, c.craft.spacecraft_id)

    row =
      Assignments.new(
        c.mission,
        c.craft.spacecraft_id,
        latest.version + 1,
        earlier.document,
        earlier.created_by,
        Map.take(earlier, [:composition_id, :effective_revision_id])
      )

    Assignments.append([%{row | application_basis: earlier.application_basis}])
    profile
  end

  # A profile with `catalog`, the craft pinned to it.
  defp profile!(c, catalog) do
    id = "profile-catalog-#{System.unique_integer([:positive])}"

    apply!(c, [
      %{
        kind: "spacecraft_profile",
        action: :create,
        entity_id: id,
        document: %{
          "display_name" => "Catalog profile",
          "downlink_protocol" => "tm",
          "uplink_protocol" => "tc",
          "composition_id" => pin!(c, catalog),
          "frame_parameters" => %{"frame_size" => 1115, "ocf_length" => 4}
        }
      }
    ])

    apply!(c, [
      %{
        kind: "spacecraft",
        action: :update,
        entity_id: c.craft.spacecraft_id,
        changes: [
          %{path: "spacecraft_type_id", value: id},
          %{path: "spacecraft_type_version", value: 1}
        ]
      }
    ])

    id
  end

  defp request!(c, state, opts \\ []) do
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

  defp yaml_with_apid(apid) do
    """
    packets:
      - name: P#{apid}
        apid: #{apid}
        items:
          - name: v
            data_type: uint
            bit_offset: 0
            bit_size: 8
    commands: []
    """
  end

  defp switch(id, key, value),
    do: %{
      kind: "spacecraft",
      action: :update,
      entity_id: id,
      changes: [%{path: key, value: value}]
    }

  # D3 (#544): a profile pins the catalog revision's one-layer composition; Cadence derives the
  # catalog revision from it.
  defp pin!(c, catalog) do
    {:ok, composition} =
      CompositionPins.for_catalog_revision(c.org, c.mission.mission_id, catalog)

    composition
  end

  defp update(kind, id, path, value),
    do: %{kind: kind, action: :update, entity_id: id, changes: [%{path: path, value: value}]}

  defp stage(c, ops),
    do: Configuration.stage(c.scope, c.mission.mission_id, %{summary: "Catalog"}, ops)

  defp apply!(c, ops) do
    {:ok, staged} = stage(c, ops)
    {:ok, %{state: :applied}} = submit(c, staged)
  end

  defp submit(c, staged) do
    Configuration.submit(c.scope, c.mission.mission_id, staged.change_set_id, %{
      reason: "Catalog generation test",
      expected_version: staged.version,
      acknowledged_holds: true
    })
  end

  defp configure(scope, mission, craft, catalog) do
    {:ok, %{status: :succeeded}} = try_configure(scope, mission, craft, catalog)
  end

  defp try_configure(scope, mission, craft, catalog) do
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
    ControlActivations.execute(approved)
  end
end
