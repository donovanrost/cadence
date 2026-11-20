defmodule Cadence.Telemetry.HistoryStoreQuestDBTest do
  @moduledoc """
  P1 (api-ops' share): the history and plot reads against a REAL QuestDB. Production reads
  telemetry history from QuestDB (`HistoryStore.QuestDB` → `ObservationReader`), while the rest of
  the suite reads Postgres, so this is where QuestDB's own SQL shows: the canonical selection
  through Postgres identity states, native decimation (`SAMPLE BY`), and the watermark.

  The samples arrive the production way, a TCP downlink through the journal into
  `Writers.QuestDB` (QuestDBCase), and are read through the same facades the console uses:
  `Reads.Telemetry` and `Reads.PointHistory` (the console's point plot).
  """
  use Cadence.RuntimeCase, async: false

  import Cadence.TestSupport.QuestDBCase
  import Cadence.TestSupport.TCPContactFixture

  alias Cadence.Reads.PointHistory
  alias Cadence.Reads.Telemetry, as: TelemetryReads

  @moduletag :questdb

  @frames 8

  setup :setup_questdb

  setup c do
    contact = start_tcp_contact!()
    ingested = ingest_frames!(contact, 300..(300 + @frames - 1), c.questdb_since)
    [point_id] = ingested |> Enum.map(& &1["point_id"]) |> Enum.uniq()

    # The window the reads ask for: generation time, around the receipts.
    receipts = Enum.map(ingested, &parse_time!(&1["receipt_time"]))

    {:ok,
     contact: contact,
     point_id: point_id,
     receipts: receipts,
     from: DateTime.add(List.first(receipts), -60, :second),
     to: DateTime.add(List.last(receipts), 60, :second)}
  end

  # #491: frames that arrive in one socket read share a receipt time (RawEvidence, microseconds),
  # in production as here; the read breaks ties by sample_id (ObservationReader.order_clause), so
  # the order is still deterministic.
  test "history returns every canonical sample once, in receipt then sample order", c do
    assert {:ok, %{samples: samples}} =
             TelemetryReads.sample_history_result(
               c.contact.organization_id,
               c.contact.mission_id,
               c.point_id,
               from_observed_at: c.from,
               to_observed_at: c.to,
               order: :asc,
               limit: 100
             )

    assert length(samples) == @frames
    assert samples |> Enum.map(& &1.sample_id) |> Enum.uniq() |> length() == @frames
    assert Enum.map(samples, & &1.receipt_time) == Enum.sort(c.receipts, DateTime)
    assert samples == Enum.sort(samples, &read_order?/2)
    assert Enum.all?(samples, &(&1.point_id == c.point_id))
    # The fixture's packet carries sc_mode = 4 in every frame.
    assert Enum.all?(
             samples,
             &(numeric(&1.raw_value) == 4 and numeric(&1.engineering_value) == 4)
           )
  end

  test "history honours the window and the limit", c do
    [_first, second | _rest] = Enum.sort(c.receipts, DateTime)

    assert {:ok, %{samples: later}} =
             TelemetryReads.sample_history_result(
               c.contact.organization_id,
               c.contact.mission_id,
               c.point_id,
               from_observed_at: second,
               to_observed_at: c.to,
               order: :asc,
               limit: 100
             )

    assert length(later) == @frames - 1

    assert {:ok, %{samples: limited}} =
             TelemetryReads.sample_history_result(
               c.contact.organization_id,
               c.contact.mission_id,
               c.point_id,
               from_observed_at: c.from,
               to_observed_at: c.to,
               order: :asc,
               limit: 3
             )

    assert length(limited) == 3
  end

  test "the point plot uses QuestDB's native decimation and counts every sample once", c do
    assert {:ok, %{buckets: buckets, truncated: false}} =
             PointHistory.load(
               c.contact.organization_id,
               c.contact.mission_id,
               c.point_id,
               %{from: c.from, to: c.to, max_points: 10, spacecraft_id: c.contact.spacecraft_id}
             )

    assert buckets != []
    assert buckets |> Enum.map(& &1.count) |> Enum.sum() == @frames
    assert Enum.all?(buckets, &(numeric(&1.min) == 4 and numeric(&1.max) == 4))
    assert Enum.all?(buckets, &(numeric(&1.mean) == 4))
  end

  test "the watermark is the point's latest receipt", c do
    assert {:ok, watermark} =
             TelemetryReads.sample_watermark(
               c.contact.organization_id,
               c.contact.mission_id,
               c.point_id,
               []
             )

    latest = Enum.max(c.receipts, DateTime)
    first = Enum.min(c.receipts, DateTime)

    assert %{sample_count: @frames, latest_receipt_time: %DateTime{} = latest_receipt} = watermark
    assert DateTime.compare(latest_receipt, latest) == :eq
    assert DateTime.compare(watermark.retention_starts_at, first) == :eq
  end

  # The history read's own order (ObservationReader.order_clause): receipt time, then sample id.
  defp read_order?(a, b) do
    case DateTime.compare(a.receipt_time, b.receipt_time) do
      :lt -> true
      :gt -> false
      :eq -> a.sample_id <= b.sample_id
    end
  end

  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value), do: value

  defp parse_time!(%DateTime{} = at), do: at

  defp parse_time!(text) when is_binary(text) do
    {:ok, at, _offset} = DateTime.from_iso8601(text)
    at
  end
end
