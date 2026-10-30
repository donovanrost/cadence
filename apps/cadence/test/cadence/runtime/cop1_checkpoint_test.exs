defmodule Cadence.Runtime.COP1CheckpointTest do
  use Cadence.UnitCase, async: true
  alias Cadence.ActionRequests.UplinkRequest
  alias Cadence.Capabilities.ExecutionContext
  alias Cadence.Capabilities.TransportExtensions.UplinkGateway
  alias Cadence.Runtime.ProtocolCheckpoint.Data
  alias CCSDS.Transport.COP1.CLCW

  @context %ExecutionContext{current_time: ~U[2026-10-28 00:00:00Z]}
  @config %{
    cop1_mode: :fop,
    frame_size: 32,
    vcid: 3,
    scid: 7,
    cop1_window_size: 4,
    initial_frame_seq: 255,
    segment_header_flag: 1
  }

  test "versioned JSON round trip preserves sequence wrap, integer APIDs, exact frames and retries" do
    fresh = fresh()
    state = %{fresh | packet_sequence_counts: %{19 => 16_383}}

    request =
      request(%{
        command_release_attempt_id: "attempt",
        command_request_id: "request",
        command_queue_entry_id: "queue",
        command_name: "TEST",
        layout_kind: :space_packet,
        apid: 19,
        encoded_binary_base64: Base.encode64(<<1, 2>>),
        encoded_size_bytes: 2
      })

    {:ok, result} = UplinkGateway.handle_control_input(request, state, @context)
    assert result.state.next_frame_seq == 0
    assert result.state.packet_sequence_counts == %{19 => 0}
    {:ok, retried} = UplinkGateway.handle_timer("cop1:t1:3", result.state, @context)
    {:ok, document} = UplinkGateway.export_checkpoint(retried.state, @context)
    json = document |> Jason.encode!() |> Jason.decode!()
    assert {:ok, restored} = UplinkGateway.restore_checkpoint(json, fresh, @context)
    assert restored.state == retried.state
    assert restored.action_requests == []
    assert restored.records == []
    assert hd(restored.state.cop1.sent_queue).frame.retries == 1
    assert restored.state.cop1.timer_running
  end

  test "acknowledged state restores without resurrecting frames" do
    fresh = fresh()

    request =
      request(%{
        command_release_attempt_id: "a",
        command_request_id: "r",
        encoded_binary_base64: Base.encode64(<<1>>),
        encoded_size_bytes: 1
      })

    {:ok, result} = UplinkGateway.handle_control_input(request, fresh, @context)

    {:ok, acked} =
      UplinkGateway.handle_transport_event(
        %CLCW{vcid: 3, report_value: 0},
        result.state,
        @context
      )

    {:ok, checkpoint} = UplinkGateway.export_checkpoint(acked.state, @context)
    assert {:ok, restored} = UplinkGateway.restore_checkpoint(checkpoint, fresh, @context)
    assert restored.state == acked.state
    assert restored.state.cop1.sent_queue == []
  end

  test "rejects unsupported versions, changed configuration and inconsistent frame state" do
    fresh = fresh()
    {:ok, document} = UplinkGateway.export_checkpoint(fresh, @context)

    assert {:error, :unsupported_protocol_checkpoint_version} =
             UplinkGateway.restore_checkpoint(
               %{document | "schema_version" => 2},
               fresh,
               @context
             )

    assert {:error, :invalid_cop1_checkpoint} =
             UplinkGateway.restore_checkpoint(document, %{fresh | vcid: 4}, @context)

    {:ok, bad_state} = Data.encode(%{fresh | next_frame_seq: 1})

    assert {:error, :invalid_cop1_checkpoint} =
             UplinkGateway.restore_checkpoint(%{document | "state" => bad_state}, fresh, @context)

    {:ok, bad_state} = Data.encode(%{fresh | packet_sequence_counts: %{19 => 16_384}})

    assert {:error, :invalid_cop1_checkpoint} =
             UplinkGateway.restore_checkpoint(%{document | "state" => bad_state}, fresh, @context)
  end

  test "rejects missing frames and altered wire identities" do
    fresh = fresh()

    request =
      request(%{
        command_release_attempt_id: "a",
        command_request_id: "r",
        encoded_binary_base64: Base.encode64(<<1>>),
        encoded_size_bytes: 1
      })

    {:ok, result} = UplinkGateway.handle_control_input(request, fresh, @context)
    {:ok, document} = UplinkGateway.export_checkpoint(result.state, @context)

    for cop1 <- [
          %{result.state.cop1 | sent_queue: []},
          %{
            result.state.cop1
            | sent_queue:
                Enum.map(result.state.cop1.sent_queue, fn entry ->
                  %{entry | frame: %{entry.frame | seq: 7}}
                end)
          }
        ] do
      {:ok, bad_state} = Data.encode(%{result.state | cop1: cop1})

      assert {:error, :invalid_cop1_checkpoint} =
               UplinkGateway.restore_checkpoint(
                 %{document | "state" => bad_state},
                 fresh,
                 @context
               )
    end
  end

  test "data codec rejects process capabilities, arbitrary structs, unknown atoms and duplicate keys" do
    for value <- [self(), make_ref(), fn -> :ok end, %URI{scheme: "test"}] do
      assert {:error, :invalid_checkpoint_data} = Data.encode(value)
    end

    assert {:error, :invalid_checkpoint_data} =
             Data.decode(["atom", "checkpoint_atom_that_must_not_exist_826194"])

    assert {:error, :invalid_checkpoint_data} = Data.decode(["map", [[1, 2], [1, 3]]])

    assert {:error, :invalid_checkpoint_data} =
             Data.decode(["external_term", Base.encode64(:erlang.term_to_binary(fresh()))])

    {:ok, data} = Data.encode(%{"binary" => <<0, 255>>, 7 => {:tc, 1}, nested: [1, 1.5, nil]})

    assert {:ok, %{"binary" => <<0, 255>>, 7 => {:tc, 1}, nested: [1, 1.5, nil]}} =
             Data.decode(data)
  end

  test "direct and bypass modes have no restoration qualification" do
    {:ok, direct} = UplinkGateway.init_transport(%{@config | cop1_mode: :disabled}, @context)

    assert {:error, :unsupported_protocol_restoration} =
             UplinkGateway.export_checkpoint(direct.state, @context)

    assert {:error, :invalid_cop1_checkpoint} =
             UplinkGateway.export_checkpoint(Map.put(fresh(), :bypass_flag, 1), @context)
  end

  defp request(attrs) do
    UplinkRequest.new(
      Map.merge(
        %{
          command_queue_entry_id: "queue",
          source_endpoint_ref: "endpoint",
          mission_model_revision_id: "model",
          command_id: "command"
        },
        attrs
      )
    )
  end

  defp fresh do
    {:ok, result} = UplinkGateway.init_transport(@config, @context)
    result.state
  end
end
