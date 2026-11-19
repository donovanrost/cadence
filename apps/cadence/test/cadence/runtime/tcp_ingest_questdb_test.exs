defmodule Cadence.Runtime.TCPIngestQuestDBTest do
  @moduledoc """
  P1 (docs/ci/questdb-integration.md; api-ops' share, ingest): a TCP downlink ingested end to end
  into a REAL QuestDB, journal → processing → Writers.QuestDB. Production writes telemetry here,
  while the rest of the suite swaps in Postgres, so this is where QuestDB's own behaviour shows:
  the asynchronous WAL, DEDUP UPSERT KEYS instead of unique errors, and the identity columns.
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.QuestDBCase
  import Cadence.TestSupport.TCPContactFixture

  @moduletag :questdb

  setup :setup_questdb

  test "every frame lands in QuestDB once, with its own receipt time and identity", c do
    %{mission_id: mission_id, port: port} = start_tcp_contact!()
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, packet: 0, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)

    for count <- 200..207 do
      assert :ok = :gen_tcp.send(socket, frame(count))
      Process.sleep(50)
    end

    rows =
      read_back(fn ->
        case rows(mission_id, c.questdb_since) do
          rows when length(rows) >= 8 -> {:ok, rows}
          rows -> rows
        end
      end)

    # One packet with one point per frame (the fixture's catalog): 8 rows, no more, no fewer.
    assert length(rows) == 8, "expected 8 rows in QuestDB, got #{length(rows)}"
    assert rows |> Enum.map(& &1["receipt_time"]) |> Enum.uniq() |> length() == 8
    assert rows |> Enum.map(& &1["observation_identity_id"]) |> Enum.uniq() |> length() == 8
    assert Enum.all?(rows, &(&1["validity_state"] == "canonical"))
    assert rows |> Enum.map(& &1["idempotency_key"]) |> Enum.uniq() |> length() == 8
  end
end
