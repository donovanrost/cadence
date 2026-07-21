defmodule Cadence.CCSDS.Transport.COP1.FOPTest do
  use ExUnit.Case, async: true

  alias Cadence.CCSDS.Transport.COP1.{CLCW, FOP}

  test "starts a release and completes it when the CLCW report advances" do
    state =
      FOP.new(%{
        enabled: true,
        vcid: 0,
        timeout_ms: 100,
        max_retransmit: 2
      })

    base_request = %{
      command_release_attempt_id: "release-1",
      command_request_id: "request-1",
      command_name: "NOOP",
      source_endpoint_ref: "endpoint-1"
    }

    frames = [%{seq: 0, frame_base64: Base.encode64(<<1, 2, 3>>)}]

    assert {:ok, start_transition} = FOP.accept_release(state, base_request, frames)

    assert start_transition.signal ==
             {:start, release_metadata("release-1", "request-1", "NOOP", "endpoint-1")}

    assert start_transition.schedule_timeout_seqs == [0]

    assert {:ok, completion_transition} =
             FOP.apply_clcw(
               start_transition.state,
               CLCW.new(%{vcid: 0, report_value: 1})
             )

    assert completion_transition.cancel_timeout_seqs == [0]

    assert completion_transition.signal ==
             {:completion, release_metadata("release-1", "request-1", "NOOP", "endpoint-1")}
  end

  defp release_metadata(
         command_release_attempt_id,
         command_request_id,
         command_name,
         source_endpoint_ref
       ) do
    %{
      command_release_attempt_id: command_release_attempt_id,
      command_request_id: command_request_id,
      command_name: command_name,
      source_endpoint_ref: source_endpoint_ref
    }
  end
end
