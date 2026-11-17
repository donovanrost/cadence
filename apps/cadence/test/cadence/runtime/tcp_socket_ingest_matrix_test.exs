defmodule Cadence.Runtime.TCPSocketIngestMatrixTest do
  @moduledoc """
  The TCP downlink end to end, with the ingress journal on AND off (production's default is off):
  every frame lands, each with its own receipt time and its own observation identity, and none is
  dropped (DECISIONS #83, docs/apogee/plans/ingress-time-tags.md).
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.TCPContactFixture

  alias Cadence.Ingress.ReceiveBackpressure

  @moduletag :ingest_journal_matrix

  test "every frame lands with its own receipt time and identity, and none is dropped" do
    %{mission_id: mission_id, port: port} = start_tcp_contact!()
    test_pid = self()
    handler = "tcp-ingest-matrix-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler,
        ReceiveBackpressure.dropped_event(),
        fn _event, measurements, _metadata, _config ->
          send(test_pid, {:dropped, measurements})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 0, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)

    for count <- 100..107 do
      assert :ok = :gen_tcp.send(socket, frame(count))
      Process.sleep(50)
    end

    rows = wait_for_rows(mission_id, 8)
    assert length(rows) == 8, "no frame may be lost"

    times = rows |> Enum.map(& &1.receipt_time) |> Enum.sort(DateTime)
    assert length(Enum.uniq(times)) == 8, "each frame keeps its own receipt time"

    # Each frame its own identity. First-seen rule (11-17): a canonical sighting writes no
    # identity-state row, so the identities are read from the stored samples.
    identities = Enum.map(rows, & &1.provenance["storage"]["observation_identity_id"])
    assert identities |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length() == 8
    refute_received {:dropped, _measurements}
  end
end
