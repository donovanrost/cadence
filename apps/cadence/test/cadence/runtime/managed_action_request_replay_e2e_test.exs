defmodule Cadence.Runtime.ManagedActionRequestReplayE2ETest do
  @moduledoc """
  DECISIONS #99 for managed action requests, end to end (lead 11-17, R3). A live partition runs a
  packet counter that asks for a flush timer on the first packet it handles. The same journal
  bytes are processed, the partition owner is killed (a restart re-initializes the application,
  so it asks again), and the journal replays the bytes re-cut mid-frame: the request is stored
  once, under the same replay-safe id, and the tripwire (action kind, timer key, delay) doesn't
  fire on the honest re-batched replay.
  """
  use Cadence.RuntimeCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Cadence.ApplicationDispatch.{
    BindingRule,
    BindingSet,
    CapabilityConfig,
    CapabilityInstance
  }

  alias Cadence.Ingress.RawEvidence
  alias Cadence.Platform.ReplayId
  alias Cadence.Runtime
  alias Cadence.Runtime.ManagedRecords.{ManagedActionRequestRow, ManagedCapabilityRecordRow}
  alias Cadence.Runtime.{PartitionKey, PartitionOwner}
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias CCSDS.Core.SDUOctets
  alias CCSDS.SDLP.TM.Segmentation

  @frame_size 10

  setup do
    mission_id =
      "mission-request-replay-" <> Integer.to_string(System.unique_integer([:positive]))

    on_exit(fn -> Runtime.stop_mission(mission_id) end)

    endpoint = persist_source_endpoint(mission_id)
    binding_set = packet_counter_binding_set(mission_id, endpoint.source_endpoint_id)
    {:ok, ^binding_set} = Cadence.Governance.persist_binding_set(binding_set)

    {:ok, _activation} =
      Cadence.ActivationFixtures.activate_binding_set(
        mission_id,
        binding_set.binding_set_id,
        binding_set.version
      )

    %{mission_id: mission_id, endpoint: endpoint}
  end

  test "a re-batched replay after a restart finds the same request", c do
    bytes = frames()

    log =
      capture_log(fn ->
        {:ok, _} = Cadence.process_telemetry_ingress(evidence(c, bytes, 0))
        [first] = request_ids(c)
        assert {:ok, %{kind: :managed_action_request}} = ReplayId.parse(first)

        kill_partition!(c)

        cut = div(@frame_size, 2) + 1
        <<head::binary-size(^cut), tail::binary>> = bytes
        {:ok, _} = Cadence.process_telemetry_ingress(evidence(c, head, 0))
        {:ok, _} = Cadence.process_telemetry_ingress(evidence(c, tail, cut))

        # The replay really asked again (the restart re-initialized the counter), so the writer
        # met the stored id rather than having nothing to write.
        assert requests_emitted(c) == 2
        assert request_ids(c) == [first]
      end)

    refute log =~ "MM_REPLAY_ID_CONFLICT"
  end

  defp requests_emitted(c) do
    ManagedCapabilityRecordRow
    |> where([row], row.mission_id == ^c.mission_id and row.event_kind == "record_handled")
    |> select([row], sum(row.action_request_count))
    |> Repo.one()
  end

  defp request_ids(c) do
    ManagedActionRequestRow
    |> where([row], row.mission_id == ^c.mission_id)
    |> select([row], row.action_request_id)
    |> Repo.all()
    |> Enum.sort()
  end

  defp kill_partition!(c) do
    key = %PartitionKey{affinity: :source_endpoint, value: c.endpoint.source_endpoint_id}
    {:ok, owner} = PartitionOwner.lookup(c.mission_id, key)
    Process.exit(owner, :kill)

    await(fn ->
      match?({:ok, pid} when pid != owner, PartitionOwner.lookup(c.mission_id, key))
    end)
  end

  defp await(fun, attempts \\ 100)
  defp await(_fun, 0), do: flunk("condition was not satisfied in time")

  defp await(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(50)
      await(fun, attempts - 1)
    end
  end

  # Journal records of 2 bytes, 1 ms apart: a batch is whole records, whatever its boundaries.
  defp evidence(c, bytes, offset) do
    RawEvidence.new(%{
      mission_id: c.mission_id,
      source_ref: "provider/station-a",
      protocol_family: :tm,
      receipt_time: ~U[2026-11-17 01:00:00.000000Z],
      receipt_times:
        for(
          start <- offset..(offset + byte_size(bytes) - 1)//2,
          do: {start, DateTime.add(~U[2026-11-17 01:00:00.000000Z], start, :millisecond)}
        ),
      raw: bytes,
      metadata: %{
        "journal_stream_id" => "request-replay-stream",
        "journal_start_offset" => offset,
        "journal_end_offset" => offset + byte_size(bytes),
        frame_size: @frame_size,
        ocf_length: 0
      }
    })
  end

  defp frames do
    packet = <<0::3, 0::1, 0::1, 42::11, 3::2, 1::14, 1::16, 0, 7>>

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

    {:ok, state} = Segmentation.init([])

    {:ok, encoded, _state} =
      Segmentation.segment_encode(sdu, %{frame_size: @frame_size, ocf_length: 0}, state, [])

    IO.iodata_to_binary(encoded)
  end

  # A flush interval far past the test, so the timer never fires during it.
  defp packet_counter_binding_set(mission_id, source_endpoint_ref) do
    BindingSet.new(%{
      mission_id: mission_id,
      binding_set_id: "request-replay-basis",
      version: 1,
      capability_instances: [
        CapabilityInstance.new(%{
          capability_instance_id: "packet-counter-instance-v1",
          family_key: :packet_counter,
          target_scope: :source_endpoint,
          source_endpoint_ref: source_endpoint_ref,
          capability_config:
            CapabilityConfig.inline(%{
              "metric_name" => "packet_window",
              "flush_interval_ms" => 600_000
            })
        })
      ],
      rules: [
        BindingRule.new(%{
          binding_rule_id: "packet-counter-rule-v1",
          capability_instance_id: "packet-counter-instance-v1",
          selector: %{
            scope: %{target_scope: :source_endpoint, source_endpoint_ref: source_endpoint_ref},
            match: %{packet_kind: :space_packet, apid: 42}
          },
          fanout_mode: :multi,
          priority: 10
        })
      ]
    })
  end

  defp persist_source_endpoint(mission_id) do
    {:ok, _} =
      Cadence.SpacecraftStore.persist_spacecraft(
        Spacecraft.new(%{
          spacecraft_id: "sc-alpha",
          mission_id: mission_id,
          display_name: "SC Alpha"
        })
      )

    {:ok, endpoint} =
      Cadence.SourceEndpoints.persist_source_endpoint(
        SourceEndpoint.new(%{
          source_endpoint_id: "endpoint-sc-alpha",
          mission_id: mission_id,
          spacecraft_id: "sc-alpha",
          source_ref: "provider/station-a"
        })
      )

    endpoint
  end
end
