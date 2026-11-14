defmodule Cadence.Ingress.ReceiveBackpressureTest do
  @moduledoc "DECISIONS #83: a full receive buffer pauses a push-back transport and never drops silently."
  use ExUnit.Case, async: false

  alias Cadence.Ingress.ReceiveBackpressure

  # The one non-push-back transport (no UDP adapter exists): it admits frames into a bounded
  # buffer and asks the seam what to do when the buffer is full.
  defmodule TestTransport do
    @moduledoc false
    def receive_frames(frames, capacity, push_back?) do
      Enum.reduce(frames, %{buffer: [], paused?: false, dropped: 0}, fn frame, acc ->
        if length(acc.buffer) < capacity,
          do: %{acc | buffer: acc.buffer ++ [frame]},
          else: overflow(acc, frame, push_back?)
      end)
    end

    defp overflow(acc, frame, push_back?) do
      case ReceiveBackpressure.on_full(push_back?, %{buffer: :executor}, byte_size(frame)) do
        :drop -> %{acc | dropped: acc.dropped + 1}
        :pause -> %{acc | paused?: true}
      end
    end
  end

  setup do
    handler = "receive-backpressure-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler,
        [ReceiveBackpressure.paused_event(), ReceiveBackpressure.dropped_event()],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:backpressure, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  test "a transport that can't push back drops what doesn't fit, counting every frame" do
    frames = for i <- 1..5, do: <<i, 0, 0, 0>>

    assert %{buffer: kept, dropped: 2, paused?: false} =
             TestTransport.receive_frames(frames, 3, false)

    assert length(kept) == 3
    dropped = ReceiveBackpressure.dropped_event()

    for _frame <- 1..2 do
      assert_receive {:backpressure, ^dropped, %{count: 1, bytes: 4}, %{buffer: :executor}}
    end

    refute_receive {:backpressure, _event, _measurements, _metadata}
  end

  test "a transport that can push back pauses and drops nothing" do
    frames = for i <- 1..5, do: <<i>>

    assert %{dropped: 0, paused?: true} = TestTransport.receive_frames(frames, 3, true)

    paused = ReceiveBackpressure.paused_event()
    assert_receive {:backpressure, ^paused, %{count: 1}, _metadata}
    refute_receive {:backpressure, [:cadence, :ingress, :frames_dropped], _, _}
  end
end
