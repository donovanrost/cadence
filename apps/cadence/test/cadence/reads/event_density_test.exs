defmodule Cadence.Reads.EventDensityTest do
  @moduledoc """
  lead 11-15: the Timeline density bar counts in SQL. It agrees with the per-entry count, and a
  60k-row mission (mostly watermarks) answers fast without loading rows.
  """
  use Cadence.DataCase, async: false

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event
  alias Cadence.OperationalEvents.EventRow, as: OperationalEventRow
  alias Cadence.Reads.EventLog

  @org "org-density"
  @default ~w(limit flight_event contact command config operator)

  setup do
    mission = "mission-density-#{System.unique_integer([:positive])}"
    Cadence.DataCase.persist_mission_scope(@org, mission)
    %{mission: mission, now: DateTime.utc_now() |> DateTime.truncate(:second)}
  end

  defp event!(mission, kind, at, attrs) do
    %{
      event_id: "#{kind}-#{System.unique_integer([:positive])}",
      organization_id: @org,
      mission_id: mission,
      occurred_at: at,
      recorded_at: at,
      effective_at: at,
      category: :data_source,
      kind: kind,
      severity: :info,
      subject: %{kind: :data_source, id: "questdb"}
    }
    |> Map.merge(attrs)
    |> Event.new()
    |> OperationalEvents.persist_event()
  end

  defp opts(now, kinds),
    do: %{from: DateTime.add(now, -3_600), to: DateTime.add(now, 60), bucket_s: 600, kinds: kinds}

  test "the SQL count matches the per-entry count, with and without housekeeping", c do
    for i <- 1..5,
        do:
          {:ok, _} =
            event!(c.mission, :source_watermark_advanced, DateTime.add(c.now, -60 * i), %{})

    {:ok, _} =
      event!(c.mission, :source_watermark_retreated, DateTime.add(c.now, -700), %{
        replay_run_id: "replay-1"
      })

    {:ok, _} = event!(c.mission, :source_watermark_retreated, DateTime.add(c.now, -800), %{})

    {:ok, _} =
      event!(c.mission, :source_health_recovered, DateTime.add(c.now, -900), %{severity: :info})

    {:ok, _} =
      event!(c.mission, :contact_window_moved, DateTime.add(c.now, -1_000), %{
        category: :contact,
        severity: :warning,
        subject: %{kind: :contact, id: "realized-1"}
      })

    for kinds <- [nil, ["data"], @default] do
      sql = EventLog.density(@org, c.mission, opts(c.now, kinds))
      loaded = EventLog.loaded_density(@org, c.mission, opts(c.now, kinds))
      assert sql.buckets == loaded.buckets, "kinds #{inspect(kinds)}"
    end

    total = fn d ->
      Enum.sum(for b <- d.buckets, k <- [:critical, :caution, :nominal, :info], do: b[k])
    end

    assert total.(EventLog.density(@org, c.mission, opts(c.now, ["data"]))) == 8
    assert total.(EventLog.density(@org, c.mission, opts(c.now, @default))) == 1
  end

  # The guarantee is that the count happens in SQL: no query loads the rows (asserted by row counts,
  # not wall-clock time, which flaked under load; lead 11-16).
  test "60k watermark rows: data-kind density is counted in SQL without loading the rows", c do
    payload = %{"value" => %{"source_payload" => %{"sample_ids" => List.duplicate("x", 120)}}}
    stamp = %{c.now | microsecond: {0, 6}}

    1..60_000
    |> Stream.map(fn i ->
      at = DateTime.add(stamp, -rem(i, 3_500))

      %{
        event_id: "wm-#{i}",
        organization_id: @org,
        mission_id: c.mission,
        occurred_at: at,
        recorded_at: at,
        effective_at: at,
        category: "data_source",
        kind: "source_watermark_advanced",
        severity: "info",
        subject_kind: "data_source",
        subject_id: "source-#{i}",
        actor_document: %{},
        scope_document: %{},
        causality_document: %{},
        payload_document: payload,
        previous_document: %{},
        current_document: %{},
        metadata_document: payload,
        inserted_at: at
      }
    end)
    |> Stream.chunk_every(2_000)
    |> Enum.each(&Repo.insert_all(OperationalEventRow, &1))

    handler = "density-rows-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:cadence, :repo, :query],
      fn _event, _measure, meta, _ ->
        case meta[:result] do
          {:ok, %{num_rows: rows}} -> send(test_pid, {:rows, rows})
          _other -> :ok
        end
      end,
      nil
    )

    density = EventLog.density(@org, c.mission, opts(c.now, ["data"]))

    :telemetry.detach(handler)

    rows =
      Stream.repeatedly(fn -> receive do: ({:rows, n} -> n), after: (0 -> nil) end)
      |> Enum.take_while(& &1)

    assert Enum.max(rows, fn -> 0 end) < 1_000, "a query returned #{Enum.max(rows)} rows"

    assert Enum.sum(for b <- density.buckets, do: b.info) == 60_000
  end
end
