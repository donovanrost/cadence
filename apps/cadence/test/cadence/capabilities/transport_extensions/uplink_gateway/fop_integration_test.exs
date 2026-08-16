defmodule Cadence.Capabilities.TransportExtensions.UplinkGateway.FOPIntegrationTest do
  use Cadence.UnitCase, async: true

  alias Cadence.ActionRequests.{CancelTimer, ScheduleTimer, UplinkRequest}
  alias Cadence.Capabilities.{ExecutionContext, TransportExtensions.UplinkGateway}
  alias Cadence.CCSDS.Transport.COP1.CLCW
  alias Cadence.Runtime.PartitionKey

  test "initializes a full sliding window and uses one VC-scoped T1 timer" do
    assert {:ok, initialized} =
             UplinkGateway.init_transport(configuration(), execution_context())

    assert initialized.state.cop1.state == :active
    assert initialized.state.cop1.sliding_window_width == 4
    assert initialized.state.cop1.timeout_type == 1
    assert initialized.state.cop1.transmission_limit == 3

    assert {:ok, transmitted} =
             UplinkGateway.handle_control_input(
               uplink_request(),
               initialized.state,
               execution_context()
             )

    uplinks = Enum.filter(transmitted.action_requests, &match?(%UplinkRequest{}, &1))
    timers = Enum.filter(transmitted.action_requests, &match?(%ScheduleTimer{}, &1))

    assert length(uplinks) == 4
    assert [%ScheduleTimer{timer_key: "cop1:t1:0", delay_ms: 100}] = timers
    assert Enum.map(uplinks, & &1.first_frame_seq) == [0, 1, 2, 3]
    assert transmitted.state.cop1.vs == 4
    assert length(transmitted.state.cop1.sent_queue) == 4

    assert {:ok, partial} =
             UplinkGateway.handle_transport_event(
               %{kind: :cop1_clcw, clcw: CLCW.new(vcid: 0, report_value: 2)},
               transmitted.state,
               execution_context()
             )

    assert partial.action_requests == []
    assert partial.state.cop1.nnr == 2
    assert Enum.map(partial.state.cop1.sent_queue, & &1.frame.seq) == [2, 3]

    assert {:ok, completed} =
             UplinkGateway.handle_transport_event(
               %{kind: :cop1_clcw, clcw: CLCW.new(vcid: 0, report_value: 4)},
               partial.state,
               execution_context()
             )

    assert [%CancelTimer{timer_key: "cop1:t1:0"}] = completed.action_requests
    assert completed.state.cop1.sent_queue == []
    assert completed.state.cop1.in_flight_release == nil
  end

  test "one T1 expiry retransmits the complete outstanding window and restarts one timer" do
    assert {:ok, initialized} =
             UplinkGateway.init_transport(configuration(), execution_context())

    assert {:ok, transmitted} =
             UplinkGateway.handle_control_input(
               uplink_request(),
               initialized.state,
               execution_context()
             )

    assert {:ok, retransmitted} =
             UplinkGateway.handle_timer(
               "cop1:t1:0",
               transmitted.state,
               execution_context()
             )

    uplinks = Enum.filter(retransmitted.action_requests, &match?(%UplinkRequest{}, &1))
    timers = Enum.filter(retransmitted.action_requests, &match?(%ScheduleTimer{}, &1))

    assert length(uplinks) == 4
    assert Enum.all?(uplinks, &(&1.metadata["cop1_release_kind"] == "retransmit"))
    assert Enum.map(uplinks, & &1.metadata["cop1_retry_count"]) == [1, 1, 1, 1]
    assert [%ScheduleTimer{timer_key: "cop1:t1:0"}] = timers
    assert retransmitted.state.cop1.transmission_count == 2

    assert {:ok, stale_vc} =
             UplinkGateway.handle_timer(
               "cop1:t1:1",
               retransmitted.state,
               execution_context()
             )

    assert stale_vc.state == retransmitted.state
    assert stale_vc.action_requests == []
  end

  defp configuration do
    %{
      "service_name" => "cop1",
      "frame_size" => 12,
      "segment_header_flag" => 1,
      "cop1_mode" => "fop",
      "cop1_window_size" => 4,
      "cop1_timeout_ms" => 100,
      "cop1_max_retransmit" => 2,
      "cop1_timeout_type" => 1
    }
  end

  defp uplink_request do
    payload = :binary.copy(<<0xA5>>, 20)

    UplinkRequest.new(%{
      command_release_attempt_id: "release-1",
      command_queue_entry_id: "queue-1",
      command_request_id: "request-1",
      source_endpoint_ref: "source-1",
      mission_model_revision_id: "mission-model-1",
      command_id: "command-1",
      command_name: "BURST",
      layout_kind: :command,
      preferred_uplink_service: "cop1",
      encoded_binary_base64: Base.encode64(payload),
      encoded_size_bytes: byte_size(payload)
    })
  end

  defp execution_context do
    ExecutionContext.new(%{
      mission_id: "mission-1",
      activation_id: "activation-1",
      binding_set_id: "binding-set-1",
      binding_set_version: 1,
      current_time: ~U[2026-07-20 12:00:00Z],
      partition_key: PartitionKey.new(%{affinity: :transport, value: "transport-1"}),
      capability_instance_id: "uplink-gateway-1",
      scope_ref: "transport-1"
    })
  end
end
