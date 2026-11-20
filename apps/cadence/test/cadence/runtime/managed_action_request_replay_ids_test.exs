defmodule Cadence.Runtime.ManagedActionRequestReplayIdsTest do
  @moduledoc """
  DECISIONS #99 for managed action requests: an id derived from the input (the journal frame, a
  timer firing, or a managed application's initialization), numbered per input across every
  capability in the partition, and written insert-or-get. Lead's conditions (11-17): two
  capabilities answering one frame; the same input numbered again; init across a restart and a
  binding set version bump; the tripwire.
  """
  use Cadence.DataCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.ActionRequests.ScheduleTimer
  alias Cadence.ApplicationDispatch.CapabilityInstance
  alias Cadence.Capabilities.{ExecutionContext, ExecutionResult}
  alias Cadence.Platform.ReplayId
  alias Cadence.Protocol.PacketRecord
  alias Cadence.Runtime.{ManagedRecords, PartitionKey, PartitionStreamKeys, Persistence}
  alias Cadence.Runtime.PartitionOwner.{EffectIds, RuntimeRecords}

  @receipt ~U[2026-11-17 01:00:00.123456Z]

  setup do
    Cadence.DataCase.persist_mission_scope("org-replay-ids", "mission-replay-ids")
    Process.delete({EffectIds, :ordinals})
    :ok
  end

  describe "numbering" do
    test "two capabilities answering one frame get distinct ids, the same again on replay" do
      frame = {"journal-1", 1_400, @receipt}

      requests = fn ->
        packet_requests("cap-a", frame, 1) ++ packet_requests("cap-b", frame, 2)
      end

      ids = assigned_ids(requests.())

      assert length(ids) == 3
      assert length(Enum.uniq(ids)) == 3

      assert Enum.map(ids, &(ReplayId.parse(&1) |> elem(1) |> Map.take([:offset, :index]))) ==
               [
                 %{offset: 1_400, index: 0},
                 %{offset: 1_400, index: 1},
                 %{offset: 1_400, index: 2}
               ]

      # A replay numbers the same input again (a fresh partition process: no cached ordinal).
      Process.delete({EffectIds, :ordinals})
      assert assigned_ids(requests.()) == ids
    end

    test "another frame or another stream numbers from zero" do
      ids =
        assigned_ids(
          packet_requests("cap-a", {"journal-1", 1_400, @receipt}, 1) ++
            packet_requests("cap-a", {"journal-1", 1_414, @receipt}, 1) ++
            packet_requests("cap-a", {"journal-2", 1_400, @receipt}, 1)
        )

      parts = Enum.map(ids, &elem(ReplayId.parse(&1), 1))
      assert Enum.map(parts, & &1.index) == [0, 0, 0]
      assert length(Enum.uniq_by(parts, & &1.ordinal)) == 2
    end

    test "a packet without a journal position keeps an Ids.new id" do
      [id] = assigned_ids(packet_requests("cap-a", nil, 1))
      assert ReplayId.parse(id) == :error
    end
  end

  describe "initialization" do
    test "a restart's re-init gets the same request back; a new binding set version a second" do
      first = init_requests("cap-a", 3)
      :ok = persist(first)

      # Restart: a new partition process runs init again.
      Process.delete({EffectIds, :ordinals})
      :ok = persist(init_requests("cap-a", 3))
      assert length(stored()) == 1

      :ok = persist(init_requests("cap-a", 4))
      assert length(stored()) == 2
    end
  end

  describe "insert-or-get" do
    test "a replayed request is stored once" do
      requests = packet_requests("cap-a", {"journal-1", 28, @receipt}, 2)
      :ok = persist(requests)
      :ok = persist(requests)

      assert length(stored()) == 2
    end

    test "a different request under a stored id is refused, MM_REPLAY_ID_CONFLICT" do
      [request] = packet_requests("cap-a", {"journal-1", 42, @receipt}, 1)
      :ok = persist([request])

      {:ok, %{action_requests: [assigned]}} = EffectIds.assign(records([request]))

      impostor = %{
        assigned
        | request_document: %{assigned.request_document | delay_ms: 999_999},
          effect_source: nil
      }

      log =
        capture_log(fn ->
          assert {:error, {:replay_id_conflict, :managed_action_request, _id}} =
                   Persistence.persist_managed_runtime_records([], [impostor], [])
        end)

      assert log =~ "MM_REPLAY_ID_CONFLICT"
      assert length(stored()) == 1
    end
  end

  test "the stream ordinal is allocated once per partition and stream" do
    {:ok, a} = PartitionStreamKeys.ordinal("mission-replay-ids", "p1", "journal-1")
    {:ok, ^a} = PartitionStreamKeys.ordinal("mission-replay-ids", "p1", "journal-1")
    {:ok, b} = PartitionStreamKeys.ordinal("mission-replay-ids", "p2", "journal-1")
    refute a == b

    assert {:ok, %{partition_id: "p1", stream_key: "journal-1"}} = PartitionStreamKeys.fetch(a)
  end

  defp packet_requests(capability_id, frame, count) do
    packet = %PacketRecord{packet_id: "packet-1", evidence_id: "evidence-1", journal_frame: frame}

    for_execution(:packet, capability_id, 3, count, packet_record: packet)
  end

  defp init_requests(capability_id, binding_set_version),
    do: for_execution(:initialized, capability_id, binding_set_version, 1, [])

  defp for_execution(event_kind, capability_id, binding_set_version, count, opts) do
    capability =
      CapabilityInstance.new(%{
        capability_instance_id: capability_id,
        family_key: :packet_counter
      })

    context =
      ExecutionContext.new(%{
        mission_id: "mission-replay-ids",
        activation_id: "activation-1",
        binding_set_id: "binding-set-1",
        binding_set_version: binding_set_version,
        # Wall-clock processing time: it must not reach the id.
        current_time: DateTime.utc_now(),
        partition_key: %PartitionKey{affinity: :source_endpoint, value: "endpoint-1"},
        capability_instance_id: capability_id,
        scope_ref: "endpoint-1"
      })

    timers = for n <- 1..count, do: ScheduleTimer.new(%{timer_key: "t#{n}", delay_ms: 1_000})

    RuntimeRecords.for_execution(
      event_kind,
      capability,
      context,
      %ExecutionResult{},
      timers,
      [],
      opts
    ).action_requests
  end

  defp records(requests), do: %{RuntimeRecords.empty() | action_requests: requests}

  defp assigned_ids(requests) do
    {:ok, %{action_requests: assigned}} = EffectIds.assign(records(requests))
    Enum.map(assigned, & &1.action_request_id)
  end

  defp persist(requests) do
    {:ok, %{action_requests: assigned}} = EffectIds.assign(records(requests))
    Persistence.persist_managed_runtime_records([], assigned, [])
  end

  defp stored, do: ManagedRecords.list_action_requests("mission-replay-ids")
end
