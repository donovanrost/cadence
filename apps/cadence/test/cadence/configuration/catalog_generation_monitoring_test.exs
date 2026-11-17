defmodule Cadence.Configuration.CatalogGenerationMonitoringTest do
  @moduledoc """
  2026-11-12 (director, api-ops): a catalog-path generation re-admitted from the store still
  monitors. Its binding set's packet fields read back without parameter ids, so a sample's
  semantic identity must come from the mission-model plan, and a catalog limit must still fire.
  """
  use Cadence.RuntimeCase, async: false

  alias Cadence.Applications.SpacecraftConfiguration.{Drafts, Review}
  alias Cadence.Applications.TelemetryDecomFixtures, as: Fixtures
  alias Cadence.Catalog.SpacecraftConfigurationInput
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Control.Configuration
  alias Cadence.Control.MissionRuntime, as: ControlMissionRuntime
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.Management.Activations
  alias Cadence.Runtime.{MissionCoordinator, MissionModelPlanDecoder}
  alias Cadence.SemanticRuntime
  alias Cadence.SemanticRuntime.{PlanDecoder, State, Update}
  alias Cadence.Telemetry.PacketDefinition

  # HEALTH.mode carries catalog limits; 50 is past red_high.
  @limited_yaml """
  packets:
    - name: HEALTH
      apid: 42
      items:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_size: 8
          limits:
            yellow_high: 5
            red_high: 20
  commands: []
  """

  setup do
    org = "org-catalog-mon-#{System.unique_integer([:positive])}"
    mid = "mission-catalog-mon-#{System.unique_integer([:positive])}"
    {craft, revision, endpoint} = Fixtures.setup_imported_mission!(org, mid)
    {:ok, mission} = Cadence.Missions.fetch_mission(org, mid)
    scope = Fixtures.user_scope(org, "operator")
    policy = ActivationPolicy.load(org, mid)

    {:ok, _} =
      ActivationPolicy.save(scope, mid, policy.token, %{
        "value" => %{"approval_requirement" => "direct"}
      })

    configure(scope, mission, craft, revision.catalog_revision_id)

    limited =
      Fixtures.persist_imported_revision!(org, mid, revision_label: "Limits", yaml: @limited_yaml)

    %{
      org: org,
      mission: mission,
      scope: scope,
      craft: craft,
      endpoint: endpoint,
      rev1: revision.catalog_revision_id,
      limited: limited.catalog_revision_id
    }
  end

  test "after re-admission from the store, a sample gets its parameter id and a catalog limit fires",
       c do
    profile = profile!(c, c.rev1)

    {:ok, staged} =
      stage(c, [update("spacecraft_profile", profile, "catalog_revision_id", c.limited)])

    assert {:ok, %{state: :applied}} = submit(c, staged)

    # As after a restart: the reconciler rebuilds the generation from the store.
    spec = readmit!(c)

    [configured] =
      for %{runtime_configuration: %PacketDefinition{packet_name: "HEALTH"} = configured} <-
            spec.binding_set.capability_instances,
          do: configured

    # #73: the stored field keeps its parameter id; resolving against the plan agrees.
    assert [%{parameter_id: stored_parameter_id}] = configured.fields
    assert is_binary(stored_parameter_id)

    # PartitionOwner's path: resolve against the plan, decode, turn the sample into an Update.
    assert {:ok, resolved} =
             MissionModelPlanDecoder.resolve_telemetry_configuration(
               spec.runtime_plans,
               configured
             )

    [field] = resolved.fields
    assert field.parameter_id == stored_parameter_id

    update =
      Update.new(%{
        update_id: "sample-limit-#{System.unique_integer([:positive])}",
        parameter_id: field.parameter_id,
        qualified_name: field.qualified_name,
        value: 50,
        raw_value: 50,
        quality: :good,
        generation_time: DateTime.utc_now(),
        receipt_time: DateTime.utc_now(),
        producer_kind: :container,
        producer_id: resolved.packet_definition_id,
        metadata: %{mission_id: c.mission.mission_id, spacecraft_id: c.craft.spacecraft_id}
      })

    assert {:ok, result, %State{}} =
             SemanticRuntime.process(%State{}, [update], PlanDecoder.decode(spec.runtime_plans))

    assert [%{parameter_id: parameter_id, effective_state: :critical, transition: transition}] =
             Enum.filter(result.monitoring_results, & &1.transition)

    assert parameter_id == field.parameter_id
    assert transition != nil

    # COSMOS boundaries: exactly at red_high (20) is a warning (past yellow_high 5), not red.
    at_red = %{update | update_id: update.update_id <> "-at", value: 20, raw_value: 20}

    assert {:ok, at_result, %State{}} =
             SemanticRuntime.process(%State{}, [at_red], PlanDecoder.decode(spec.runtime_plans))

    assert [%{evaluated_state: :warning}] = at_result.monitoring_results
  end

  defp readmit!(c) do
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

    {:ok, spec} = MissionCoordinator.active_spec(c.mission.mission_id)
    spec
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

  defp profile!(c, catalog) do
    id = "profile-catalog-mon-#{System.unique_integer([:positive])}"

    apply!(c, [
      %{
        kind: "spacecraft_profile",
        action: :create,
        entity_id: id,
        document: %{
          "display_name" => "Monitoring profile",
          "downlink_protocol" => "tm",
          "uplink_protocol" => "tc",
          "catalog_revision_id" => catalog,
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
      reason: "Catalog monitoring test",
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
