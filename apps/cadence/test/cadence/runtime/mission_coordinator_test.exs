defmodule Cadence.Runtime.MissionCoordinatorTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Runtime
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.Segmentation

  setup do
    mission_id = "mission-runtime-" <> Integer.to_string(System.unique_integer([:positive]))

    on_exit(fn ->
      Runtime.stop_mission(mission_id)
    end)

    %{mission_id: mission_id}
  end

  test "reports only currently running mission runtimes", %{mission_id: mission_id} do
    refute mission_id in Runtime.running_mission_ids()

    assert {:ok, mission_runtime} = Runtime.ensure_mission_started(mission_id)
    assert is_pid(mission_runtime)
    assert mission_id in Runtime.running_mission_ids()

    assert :ok = Runtime.stop_mission(mission_id)
    refute mission_id in Runtime.running_mission_ids()
  end

  test "reconciliation preserves exact generation identity and reapplies after a runtime restart",
       %{mission_id: mission_id} do
    binding_set = persisted_binding_set(mission_id, 1, "HK")

    assert {:ok, _} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    assert {:ok, spec} = Runtime.Missions.applied_spec(mission_id)
    assert {:ok, observation} = Runtime.Missions.apply(spec)
    assert {:ok, ^observation} = Runtime.Missions.apply(spec)

    assert {:error, {:generation_conflict, 1}} =
             Runtime.Missions.apply(%{spec | runtime_basis_sha256: "different-basis"})

    assert :ok = Runtime.stop_mission(mission_id)
    assert {:ok, recovered} = Runtime.Missions.apply(spec)
    assert recovered.activation_id == observation.activation_id
    assert recovered.generation == observation.generation
  end

  test "processes ingress against the active mission runtime and reconciles partition owners on activation changes",
       %{mission_id: mission_id} do
    source_endpoint = persist_source_endpoint(mission_id)
    binding_set_v1 = persisted_binding_set(mission_id, 1, "HK")
    binding_set_v2 = persisted_binding_set(mission_id, 2, "THERMAL")

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission_id,
               binding_set_v1.binding_set_id,
               binding_set_v1.version
             )

    raw_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-a",
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    assert {:ok, result_v1} = Cadence.process_telemetry_ingress(raw_evidence)
    assert Enum.map(result_v1.outputs, & &1.point_name) == ["HK.counter"]
    assert result_v1.raw_evidence.source_endpoint_ref == source_endpoint.source_endpoint_id
    assert result_v1.observation_context.mission_id == mission_id
    refute Map.has_key?(result_v1, :runtime_spec)

    assert {:ok, partition_snapshot_v1} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert partition_snapshot_v1.binding_set_version == 1

    assert partition_snapshot_v1.partition_key ==
             "source_endpoint:" <> source_endpoint.source_endpoint_id

    assert partition_snapshot_v1.rule_count == 1

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission_id,
               binding_set_v2.binding_set_id,
               binding_set_v2.version
             )

    assert {:ok, result_v2} = Cadence.process_telemetry_ingress(raw_evidence)
    assert Enum.map(result_v2.outputs, & &1.point_name) == ["THERMAL.counter"]

    assert {:ok, partition_snapshot_v2} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert partition_snapshot_v2.binding_set_version == 2
    assert partition_snapshot_v2.handler_keys == [:definition_bound_telemetry]

    # The supervisor must keep a small admission reference, not the specification
    # from the owner's birth generation. A crash after activation must recover v2.
    key = partition_key(source_endpoint)
    assert {:ok, original_owner} = Runtime.PartitionOwner.lookup(mission_id, key)
    handler = gate_recovery(mission_id, key)
    Process.exit(original_owner, :kill)
    assert_receive {:recovery_started, replacement}, 1_000

    try do
      refute replacement == original_owner
      send(replacement, :release_recovery)

      assert {:ok, %{generation: 2, binding_set_version: 2}} =
               Runtime.MissionCoordinator.partition_snapshot(mission_id, key)

      assert {:ok, result_after_restart} = Cadence.process_telemetry_ingress(raw_evidence)
      assert Enum.map(result_after_restart.outputs, & &1.point_name) == ["THERMAL.counter"]
    after
      :telemetry.detach(handler)
      send(replacement, :release_recovery)
    end
  end

  test "instantiates only mission-default and matching endpoint-scoped rules in each partition",
       %{mission_id: mission_id} do
    source_endpoint_alpha =
      persist_source_endpoint(mission_id, "endpoint-sc-alpha", "sc-alpha", "provider/station-a")

    source_endpoint_beta =
      persist_source_endpoint(mission_id, "endpoint-sc-beta", "sc-beta", "provider/station-b")

    mission_definition =
      packet_definition(mission_id, "mission-default", "MISSION", 42, 1)

    beta_definition =
      packet_definition(mission_id, "beta-specific", "BETA", 42, 1)

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "runtime-scope-basis",
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "mission-default-rule",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: mission_definition
          }),
          BindingRule.new(%{
            binding_rule_id: "beta-specific-rule",
            handler_key: :definition_bound_telemetry,
            source_endpoint_ref: source_endpoint_beta.source_endpoint_id,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: beta_definition
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    alpha_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-a",
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    beta_evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-b",
        raw: build_space_packet(42, 2, <<0, 9>>)
      })

    assert {:ok, alpha_result} = Cadence.process_telemetry_ingress(alpha_evidence)
    assert Enum.map(alpha_result.outputs, & &1.point_name) == ["MISSION.counter"]

    assert {:ok, beta_result} = Cadence.process_telemetry_ingress(beta_evidence)
    assert Enum.map(beta_result.outputs, & &1.point_name) == ["BETA.counter"]

    assert {:ok, alpha_snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint_alpha.source_endpoint_id)

    assert alpha_snapshot.rule_count == 1

    assert {:ok, beta_snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint_beta.source_endpoint_id)

    assert beta_snapshot.rule_count == 2

    # A slow source must preserve its own ordering without blocking other sources.
    key = %Runtime.PartitionKey{
      affinity: :source_endpoint,
      value: source_endpoint_alpha.source_endpoint_id
    }

    {:ok, alpha_owner} = Runtime.PartitionOwner.lookup(mission_id, key)
    coordinator = Runtime.MissionRuntime.coordinator_name(mission_id)
    :ok = :sys.suspend(alpha_owner)

    request =
      :gen_server.send_request(
        coordinator,
        {:process_telemetry_ingress, alpha_result.raw_evidence}
      )

    try do
      assert {:ok, independent_result} = Cadence.process_telemetry_ingress(beta_evidence)
      assert Enum.map(independent_result.outputs, & &1.point_name) == ["BETA.counter"]
    after
      :sys.resume(alpha_owner)
    end

    assert {:reply, {:ok, _}} = :gen_server.wait_response(request, 1_000)
  end

  test "existing telemetry partitions keep processing while partition startup is busy",
       %{mission_id: mission_id} do
    _source_endpoint = persist_source_endpoint(mission_id)
    binding_set = persisted_binding_set(mission_id, 1, "HK")

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-a",
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    assert {:ok, _first_result} = Cadence.process_telemetry_ingress(evidence)
    supervisor = GenServer.whereis(Runtime.MissionRuntime.partition_supervisor_name(mission_id))
    :ok = :sys.suspend(supervisor)

    try do
      assert {:ok, result} = Cadence.process_telemetry_ingress(evidence)
      assert Enum.map(result.outputs, & &1.point_name) == ["HK.counter"]
    after
      :sys.resume(supervisor)
    end
  end

  test "cold recovery and partition queries do not block warm or other cold partitions",
       %{mission_id: mission_id} do
    %{coordinator: coordinator, alpha_evidence: alpha_evidence, beta: beta} =
      recovery_fixture(mission_id)

    gamma = persist_source_endpoint(mission_id, "endpoint-gamma", "sc-gamma", "provider/gamma")
    gamma_key = partition_key(gamma)
    handler = gate_recovery(mission_id, beta)
    snapshot = :gen_server.send_request(coordinator, {:partition_snapshot, beta})
    assert_receive {:recovery_started, owner}, 1_000

    try do
      binding = :gen_server.send_request(coordinator, {:binding_set_for_partition, beta})
      assert {:ok, spec} = GenServer.call(coordinator, :active_spec, 1_000)
      identity = Runtime.MissionRuntimeSpec.identity(spec)
      assert {:ok, _} = GenServer.call(coordinator, {:applied_identity, identity}, 1_000)
      assert {:ok, result} = Cadence.process_telemetry_ingress(alpha_evidence)
      assert Enum.map(result.outputs, & &1.point_name) == ["HK.counter"]
      assert {:ok, _} = GenServer.call(coordinator, {:partition_snapshot, gamma_key}, 1_000)
      assert :timeout = :gen_server.wait_response(snapshot, 0)
      assert :timeout = :gen_server.wait_response(binding, 0)

      send(owner, :release_recovery)
      assert {:reply, {:ok, recovered}} = :gen_server.wait_response(snapshot, 1_000)
      assert recovered.partition_key == Runtime.PartitionKey.identifier(beta)
      assert {:reply, {:ok, _}} = :gen_server.wait_response(binding, 1_000)
    after
      :telemetry.detach(handler)
      send(owner, :release_recovery)
    end
  end

  test "recovery admission is bounded and owner death releases pending callers for retry",
       %{mission_id: mission_id} do
    %{coordinator: coordinator, alpha_evidence: evidence, beta: beta} =
      recovery_fixture(mission_id)

    handler = gate_recovery(mission_id, beta)

    requests =
      for _ <- 1..32, do: :gen_server.send_request(coordinator, {:partition_snapshot, beta})

    assert_receive {:recovery_started, owner}, 1_000

    try do
      assert {:error, {:partition_busy, _}} =
               GenServer.call(coordinator, {:partition_snapshot, beta}, 1_000)

      assert {:ok, _} = Cadence.process_telemetry_ingress(evidence)
      :telemetry.detach(handler)
      Process.exit(owner, {:shutdown, :recovery_interrupted})

      for request <- requests do
        assert {:reply, {:error, {:partition_unavailable, {:shutdown, :recovery_interrupted}}}} =
                 :gen_server.wait_response(request, 1_000)
      end

      assert {:ok, _} = GenServer.call(coordinator, {:partition_snapshot, beta}, 1_000)
      assert {:ok, _} = Cadence.process_telemetry_ingress(evidence)
    after
      :telemetry.detach(handler)
      send(owner, :release_recovery)
    end
  end

  test "generation application waits for recovering owners while the coordinator stays responsive",
       %{mission_id: mission_id} do
    %{coordinator: coordinator, beta: beta} = recovery_fixture(mission_id)
    assert {:ok, original} = Runtime.Missions.applied_spec(mission_id)
    next = %{original | generation: original.generation + 1, activation_id: "next-activation"}
    handler = gate_recovery(mission_id, beta)
    snapshot = :gen_server.send_request(coordinator, {:partition_snapshot, beta})
    assert_receive {:recovery_started, owner}, 1_000

    try do
      application = :gen_server.send_request(coordinator, {:apply_spec, next})
      assert {:ok, ^original} = GenServer.call(coordinator, :active_spec, 1_000)

      duplicate =
        :gen_server.send_request(
          coordinator,
          {:applied_identity, Runtime.MissionRuntimeSpec.identity(next)}
        )

      assert {:error, {:generation_applying, 2}} =
               GenServer.call(coordinator, {:partition_snapshot, beta}, 1_000)

      assert :timeout = :gen_server.wait_response(application, 0)
      assert :timeout = :gen_server.wait_response(duplicate, 0)
      send(owner, :release_recovery)
      assert {:reply, {:ok, %{generation: 1}}} = :gen_server.wait_response(snapshot, 1_000)
      assert {:reply, {:ok, observation}} = :gen_server.wait_response(application, 1_000)
      assert observation.generation == 2
      assert {:reply, {:ok, ^observation}} = :gen_server.wait_response(duplicate, 1_000)
      assert {:ok, ^next} = Runtime.Missions.applied_spec(mission_id)

      assert {:ok, %{generation: 2}} =
               Runtime.MissionCoordinator.partition_snapshot(mission_id, beta)
    after
      :telemetry.detach(handler)
      send(owner, :release_recovery)
    end
  end

  test "supervisor restart arguments remain small while mission inspection stays exact",
       %{mission_id: mission_id} do
    %{coordinator: coordinator, beta: key} = recovery_fixture(mission_id)
    assert {:ok, original} = Runtime.Missions.applied_spec(mission_id)
    metadata = %{payload: Enum.map(1..10_000, &%{field: &1, value: &1 * 10})}
    next = %{original | generation: 2, activation_id: "compact-restart", metadata: metadata}
    assert {:ok, _} = Runtime.Missions.apply(next)
    assert {:ok, _} = GenServer.call(coordinator, {:partition_snapshot, key})
    supervisor = Runtime.MissionRuntime.partition_supervisor_name(mission_id)
    children = :sys.get_state(supervisor).children
    assert map_size(children) == 2
    assert :erts_debug.flat_size(children) * :erlang.system_info(:wordsize) < 8_192
    assert {:ok, ^next} = Runtime.Missions.applied_spec(mission_id)
    assert {:ok, summary} = Runtime.Missions.applied_summary(mission_id)
    assert summary == Runtime.MissionRuntimeSpec.summary(next)
    refute Map.has_key?(summary, :metadata)
    refute Map.has_key?(summary, :binding_set)
  end

  test "reconciliation failure retires a partially applied mission instead of acknowledging it",
       %{mission_id: mission_id} do
    %{coordinator: coordinator, beta: beta} = recovery_fixture(mission_id)
    assert {:ok, original} = Runtime.Missions.applied_spec(mission_id)
    next = %{original | generation: original.generation + 1, activation_id: "next-activation"}
    handler = gate_recovery(mission_id, beta)
    _snapshot = :gen_server.send_request(coordinator, {:partition_snapshot, beta})
    assert_receive {:recovery_started, owner}, 1_000

    try do
      monitor = Process.monitor(GenServer.whereis(coordinator))
      application = :gen_server.send_request(coordinator, {:apply_spec, next})
      assert {:ok, ^original} = GenServer.call(coordinator, :active_spec, 1_000)
      Process.exit(owner, {:shutdown, :recovery_interrupted})

      assert {:reply, {:error, {:partition_unavailable, {:shutdown, :recovery_interrupted}}}} =
               :gen_server.wait_response(application, 1_000)

      assert_receive {:DOWN, ^monitor, :process, _, {:partition_reconciliation_failed, _}}, 1_000
    after
      :telemetry.detach(handler)
      send(owner, :release_recovery)
    end
  end

  test "reassembles TM transfer frames across ingress calls inside the active partition",
       %{mission_id: mission_id} do
    source_endpoint = persist_source_endpoint(mission_id)
    binding_set = persisted_binding_set(mission_id, 1, "TMHK")
    frame_size = 10
    [frame_one, frame_two] = build_tm_space_packet_frames(42, 5, <<0, 11>>, frame_size)

    assert {:ok, _activation} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    raw_evidence_one =
      RawEvidence.new(%{
        mission_id: mission_id,
        protocol_family: :tm,
        source_ref: "provider/station-a",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: frame_one
      })

    raw_evidence_two =
      RawEvidence.new(%{
        mission_id: mission_id,
        protocol_family: :tm,
        source_ref: "provider/station-a",
        metadata: %{frame_size: frame_size, ocf_length: 0},
        raw: frame_two
      })

    assert {:ok, first_result} = Cadence.process_telemetry_ingress(raw_evidence_one)
    assert first_result.packet_records == []
    assert first_result.dispatch_decisions == []
    assert length(first_result.transfer_frame_records) == 1
    assert first_result.protocol_anomalies == []
    assert first_result.outputs == []

    assert {:ok, first_snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert first_snapshot.tm_packet_buffer_vcid_count == 1
    assert first_snapshot.tm_frame_remainder_bytes == 0

    assert {:ok, second_result} = Cadence.process_telemetry_ingress(raw_evidence_two)
    [packet_record] = second_result.packet_records
    [dispatch_decision] = second_result.dispatch_decisions

    assert length(second_result.transfer_frame_records) == 1
    assert second_result.protocol_anomalies == []
    assert Enum.map(second_result.outputs, & &1.point_name) == ["TMHK.counter"]
    assert packet_record.apid == 42
    assert dispatch_decision.status == :matched
    assert packet_record.protocol_family == :tm

    assert {:ok, second_snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert second_snapshot.tm_packet_buffer_vcid_count == 0
    assert second_snapshot.tm_frame_remainder_bytes == 0
  end

  test "ingress waits beyond the former timeout without resubmitting recovering owner work",
       %{mission_id: mission_id} do
    %{coordinator: coordinator, beta: beta, alpha_evidence: alpha} = recovery_fixture(mission_id)
    handler = gate_recovery(mission_id, beta)

    evidence = %{
      alpha
      | source_ref: "provider/beta",
        source_endpoint_ref: nil,
        spacecraft_id: nil
    }

    task = Task.async(fn -> Cadence.process_telemetry_ingress(evidence) end)
    assert_receive {:recovery_started, owner}, 1_000

    try do
      assert Task.yield(task, 5_100) == nil
      assert {:ok, _} = GenServer.call(coordinator, :active_spec, 1_000)
      send(owner, :release_recovery)
      assert {:ok, result} = Task.await(task, 2_000)
      assert Enum.map(result.outputs, & &1.point_name) == ["HK.counter"]
    after
      :telemetry.detach(handler)
      send(owner, :release_recovery)
    end
  end

  test "retrying a journal range preserves partial TM framing and its original result",
       %{mission_id: mission_id} do
    source_endpoint = persist_source_endpoint(mission_id)
    binding_set = persisted_binding_set(mission_id, 1, "TMHK")

    assert {:ok, _} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    frames = build_tm_space_packet_frames(42, 5, <<0, 11>>, 10) |> IO.iodata_to_binary()
    # A socket read ends inside a transfer frame, just as feed 2's 14,480-byte read did.
    <<prefix::binary-size(7), suffix::binary>> = frames

    evidence = fn bytes, offset ->
      RawEvidence.new(%{
        mission_id: mission_id,
        protocol_family: :tm,
        source_ref: "provider/station-a",
        raw: bytes,
        metadata: %{
          "journal_stream_id" => "retry-stream",
          "journal_start_offset" => offset,
          "journal_end_offset" => offset + byte_size(bytes),
          frame_size: 10,
          ocf_length: 0
        }
      })
    end

    first = evidence.(prefix, 0)
    assert {:ok, first_result} = Cadence.process_telemetry_ingress(first)
    assert {:ok, ^first_result} = Cadence.process_telemetry_ingress(first)

    assert {:ok, snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert snapshot.tm_frame_remainder_bytes == 7
    assert first_result.packet_records == []

    second = evidence.(suffix, 7)
    assert {:ok, second_result} = Cadence.process_telemetry_ingress(second)
    assert {:ok, ^second_result} = Cadence.process_telemetry_ingress(second)
    assert Enum.map(second_result.outputs, & &1.point_name) == ["TMHK.counter"]
    assert second_result.protocol_anomalies == []

    assert {:ok, snapshot} =
             Runtime.partition_snapshot(mission_id, source_endpoint.source_endpoint_id)

    assert snapshot.tm_frame_remainder_bytes == 0
    assert snapshot.tm_packet_buffer_vcid_count == 0
  end

  defp recovery_fixture(mission_id) do
    persist_source_endpoint(mission_id)
    beta = persist_source_endpoint(mission_id, "endpoint-beta", "sc-beta", "provider/beta")
    binding_set = persisted_binding_set(mission_id, 1, "HK")

    assert {:ok, _} =
             Cadence.ActivationFixtures.activate_binding_set(
               mission_id,
               binding_set.binding_set_id,
               binding_set.version
             )

    evidence =
      RawEvidence.new(%{
        mission_id: mission_id,
        source_ref: "provider/station-a",
        raw: build_space_packet(42, 1, <<0, 7>>)
      })

    assert {:ok, _} = Cadence.process_telemetry_ingress(evidence)

    %{
      coordinator: Runtime.MissionRuntime.coordinator_name(mission_id),
      alpha_evidence: evidence,
      beta: partition_key(beta)
    }
  end

  defp partition_key(endpoint) do
    %Runtime.PartitionKey{affinity: :source_endpoint, value: endpoint.source_endpoint_id}
  end

  defp gate_recovery(mission_id, key) do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :runtime, :partition, :recovery, :start],
        &__MODULE__.block_recovery/4,
        {self(), mission_id, Runtime.PartitionKey.identifier(key)}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    handler
  end

  @doc false
  def block_recovery(_event, _measurements, metadata, {test, mission_id, partition_id}) do
    if metadata.mission_id == mission_id and metadata.partition_id == partition_id do
      send(test, {:recovery_started, self()})

      receive do
        :release_recovery -> :ok
      after
        10_000 -> raise "test did not release partition recovery"
      end
    end
  end

  defp persisted_binding_set(mission_id, version, packet_name) do
    packet_definition =
      packet_definition(
        mission_id,
        "packet-" <> Integer.to_string(version),
        packet_name,
        42,
        version
      )

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: "runtime-basis",
        version: version,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "telemetry-rule-" <> Integer.to_string(version),
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: packet_definition
          })
        ]
      })

    assert {:ok, ^binding_set} = Cadence.Governance.persist_binding_set(binding_set)
    binding_set
  end

  defp persist_source_endpoint(mission_id) do
    persist_source_endpoint(mission_id, "endpoint-sc-alpha", "sc-alpha", "provider/station-a")
  end

  defp persist_source_endpoint(mission_id, source_endpoint_id, spacecraft_id, source_ref) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: spacecraft_id,
        mission_id: mission_id,
        display_name: spacecraft_id
      })

    assert {:ok, _persisted_spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: source_endpoint_id,
        mission_id: mission_id,
        spacecraft_id: spacecraft_id,
        source_ref: source_ref
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(source_endpoint)

    persisted_source_endpoint
  end

  defp packet_definition(mission_id, packet_definition_id, packet_name, apid, version) do
    PacketDefinition.new(%{
      mission_id: mission_id,
      packet_definition_id: packet_definition_id,
      packet_name: packet_name,
      apid: apid,
      version: version,
      fields: [
        %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
      ]
    })
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end

  defp build_tm_space_packet_frames(apid, sequence_count, packet_data, frame_size) do
    packet = build_space_packet(apid, sequence_count, packet_data)

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, segmentation_state} = Segmentation.init([])

    {:ok, encoded_frames, _segmentation_state} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: frame_size, ocf_length: 0},
        segmentation_state,
        []
      )

    for <<frame::binary-size(^frame_size) <- encoded_frames>>, do: frame
  end
end
