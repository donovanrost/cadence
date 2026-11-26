defmodule Cadence.Runtime.TCPSocketBackpressureTest do
  @moduledoc """
  11-14 00:38:36–00:40:40Z, end to end: frames that arrive while persistence is held are all kept,
  each with its own receipt time and identity (docs/apogee/plans/ingress-time-tags.md, #83). The
  merge itself is pinned in `IngressJournalTimeTagsTest`: running contacts take the journal policy
  captured at boot, and config/test.exs takes one record per batch. Journal-only (it holds the
  journal consumer), so not in the :ingest_journal_matrix; `TCPSocketIngestMatrixTest` covers the
  same guarantees both ways.
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.TCPContactFixture

  test "frames that arrive while persistence is held are all kept, each with its own time and identity" do
    %{mission_id: mission_id, port: port} = start_tcp_contact!()
    test_pid = self()
    handler = "tcp-backpressure-#{System.unique_integer([:positive])}"

    # Hold the journal consumer on its first batch, as slow persistence did.
    :ok =
      :telemetry.attach(
        handler,
        [:cadence, :ingress_journal, :processing_batch],
        fn _event, %{entries: entries}, _metadata, _config ->
          send(test_pid, {:processing_batch, self(), entries})

          if Process.get(:backpressure_held?) != true do
            Process.put(:backpressure_held?, true)

            receive do
              :release_consumer -> :ok
            after
              5_000 -> :ok
            end
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 0, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)

    assert :ok = :gen_tcp.send(socket, frame(100))
    assert_receive {:processing_batch, consumer, 1}, 2_000

    # Seven more frames, each its own socket read and journal record, while the consumer waits.
    for count <- 101..107 do
      assert :ok = :gen_tcp.send(socket, frame(count))
      Process.sleep(50)
    end

    send(consumer, :release_consumer)

    rows =
      wait_for_rows(mission_id, 8)
      |> Enum.sort_by(& &1.receipt_time, DateTime)

    assert length(rows) == 8, "no frame may be lost"
    times = Enum.map(rows, & &1.receipt_time)
    assert length(Enum.uniq(times)) == 8, "each frame keeps its own receipt time"
    assert Enum.map(rows, & &1.generation_time) == times
    assert DateTime.diff(List.last(times), Enum.at(times, 1), :millisecond) >= 250

    # Each frame its own identity. First-seen rule (11-17): a canonical sighting writes no
    # identity-state row, so the identities are read from the stored samples.
    identities = Enum.map(rows, & &1.provenance["storage"]["observation_identity_id"])
    assert identities |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length() == 8
  end
end
