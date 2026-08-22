defmodule CCSDS.Transport.COP1.FOPTest do
  use ExUnit.Case, async: true

  alias CCSDS.Test.COP1FOPFixtures
  alias CCSDS.Transport.COP1.FOP

  test "validates the standardized FOP configuration and compatibility names" do
    assert {:ok, state} =
             FOP.init(
               enabled: true,
               vcid: 63,
               state: :initial,
               timeout_ms: 250,
               max_retransmit: 4,
               initial_vs: 255,
               sliding_window_width: 8,
               timeout_type: 1
             )

    assert state.t1_initial_ms == 250
    assert state.transmission_limit == 5
    assert state.vs == 255
    assert state.nnr == 255
    assert state.timeout_type == 1

    assert {:error, {:invalid_field, :sliding_window_width, 0}} =
             FOP.init(sliding_window_width: 0)

    assert {:error, {:invalid_field, :transmission_limit, "three"}} =
             FOP.init(max_retransmit: "three")

    assert {:error, :unknown_fop_attribute} = FOP.init(unknown: true)
  end

  test "explicit AD service assigns V(S), observes K, and advances a queued FDU after ACK" do
    state = COP1FOPFixtures.state(sliding_window_width: 1, vs: 7, nnr: 7)

    assert {:ok, first} = FOP.request_ad(state, %{frame_base64: Base.encode64(<<1>>)}, :first)
    assert first.event == :e19
    assert [%{frame_type: :ad, frame: %{seq: 7}}] = first.transmit_requests
    assert first.timer_action == :start
    refute first.state.ad_out_ready

    assert {:ok, accepted} = FOP.lower_layer_response(first.state, :ad_accept)
    assert accepted.event == :e41
    assert accepted.state.ad_out_ready

    assert {:ok, queued} =
             FOP.request_ad(accepted.state, %{frame_base64: Base.encode64(<<2>>)}, :second)

    assert queued.event == :e19
    assert queued.transmit_requests == []
    assert queued.state.wait_queue.request == :second

    assert {:ok, rejected} =
             FOP.request_ad(queued.state, %{frame_base64: Base.encode64(<<3>>)}, :third)

    assert rejected.event == :e20
    assert {:fdu, :reject, :third} in rejected.notifications

    assert {:ok, after_ack} =
             FOP.apply_clcw(queued.state, COP1FOPFixtures.clcw(report_value: 8))

    assert after_ack.event == :e2
    assert {:fdu, :positive_confirm, :first} in after_ack.notifications
    assert {:fdu, :accept, :second} in after_ack.notifications
    assert [%{frame: %{seq: 8}}] = after_ack.transmit_requests
    assert after_ack.state.vs == 9
  end

  test "the release adapter starts and completes a pre-framed command release" do
    state =
      COP1FOPFixtures.state(
        lower_layer_mode: :synchronous,
        sliding_window_width: 2,
        vs: 0,
        nnr: 0
      )

    base_request = %{
      command_release_attempt_id: "release-1",
      command_request_id: "request-1",
      command_name: "NOOP",
      source_endpoint_ref: "endpoint-1"
    }

    frames = [
      %{seq: 0, frame_base64: Base.encode64(<<1, 2, 3>>)},
      %{seq: 1, frame_base64: Base.encode64(<<4, 5, 6>>)}
    ]

    assert {:ok, started} = FOP.accept_release(state, base_request, frames)
    assert started.timer_action == :start
    assert started.schedule_timeout_seqs == [0, 1]
    assert started.signal == {:start, release_metadata()}

    assert {:ok, partial} =
             FOP.apply_clcw(started.state, COP1FOPFixtures.clcw(report_value: 1))

    assert partial.event == :e6
    assert partial.signal == nil
    assert partial.cancel_timeout_seqs == [0]

    assert {:ok, completed} =
             FOP.apply_clcw(partial.state, COP1FOPFixtures.clcw(report_value: 2))

    assert completed.event == :e2
    assert completed.timer_action == :cancel
    assert completed.cancel_timeout_seqs == [1]
    assert completed.signal == {:completion, release_metadata()}
    assert completed.state.in_flight_release == nil
  end

  test "the release adapter enforces initialization, mode, sequence, and window constraints" do
    frame = %{seq: 0, frame_base64: Base.encode64(<<1>>)}
    base_request = base_request()

    assert {:error, :cop1_disabled} = FOP.accept_release(FOP.new(), base_request, [frame])

    assert {:error, :cop1_not_initialized} =
             FOP.accept_release(FOP.new(enabled: true), base_request, [frame])

    assert {:error, :explicit_lower_layer_requires_request_ad} =
             FOP.accept_release(COP1FOPFixtures.state(), base_request, [frame])

    synchronous = COP1FOPFixtures.state(lower_layer_mode: :synchronous)

    assert {:error, {:unexpected_frame_sequences, [0], [1]}} =
             FOP.accept_release(synchronous, base_request, [%{frame | seq: 1}])

    assert {:error, :cop1_window_full} =
             FOP.accept_release(
               %{synchronous | sliding_window_width: 1},
               base_request,
               [frame, %{frame | seq: 1}]
             )
  end

  defp base_request do
    %{
      command_release_attempt_id: "release-1",
      command_request_id: "request-1",
      command_name: "NOOP",
      source_endpoint_ref: "endpoint-1"
    }
  end

  defp release_metadata do
    Map.delete(base_request(), :source_endpoint_ref)
    |> Map.put(:source_endpoint_ref, "endpoint-1")
  end
end
