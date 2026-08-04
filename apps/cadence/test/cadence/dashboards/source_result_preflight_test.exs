defmodule Cadence.Dashboards.SourceResultPreflightTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    PlannedSourceRequest,
    RuntimeCacheKey,
    SourceResult,
    SourceResultPreflight
  }

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.DataSources.{DataBinding, DataSource}

  test "marks matching fresh source-result facts as usable" do
    key = source_result_key()
    result = source_result()

    assert %SourceResultPreflight{status: :usable, reasons: []} =
             SourceResultPreflight.evaluate(key, result, key)

    assert SourceResultPreflight.usable?(key, result, key)
  end

  test "marks cache stale when watermark cursor moved" do
    cached_key = source_result_key(complete_through: ~U[2026-06-17 12:00:00Z])
    current_key = source_result_key(complete_through: ~U[2026-06-17 12:05:00Z])

    assert %SourceResultPreflight{status: :stale, reasons: reasons} =
             SourceResultPreflight.evaluate(cached_key, source_result(), current_key)

    assert :watermark_moved in reasons
  end

  test "marks cache stale when binding or data source identity changed" do
    cached_key =
      source_result_key(
        source_binding_id: "flight-telemetry-binding",
        data_source_id: "flight-questdb"
      )

    current_key =
      source_result_key(
        source_binding_id: "rehearsal-telemetry-binding",
        data_source_id: "rehearsal-questdb"
      )

    assert %SourceResultPreflight{status: :stale, reasons: reasons} =
             SourceResultPreflight.evaluate(cached_key, source_result(), current_key)

    assert :binding_changed in reasons
    assert :data_source_changed in reasons
  end

  test "marks cache stale when correction or backfill cursors changed" do
    cached_key = source_result_key(correction_cursor: "corr-1", backfill_cursor: "backfill-1")
    current_key = source_result_key(correction_cursor: "corr-2", backfill_cursor: "backfill-2")

    assert %SourceResultPreflight{status: :stale, reasons: reasons} =
             SourceResultPreflight.evaluate(cached_key, source_result(), current_key)

    assert :correction_cursor_changed in reasons
    assert :backfill_cursor_changed in reasons
  end

  test "uses revision cursors as freshness evidence for non-watermarked sources" do
    key = source_result_key(data_revision: "ops-rev-1", watermark: nil)
    result = source_result(watermarks: [])

    assert %SourceResultPreflight{status: :usable, reasons: []} =
             SourceResultPreflight.evaluate(key, result, key)
  end

  test "marks non-watermarked cache stale when revision cursor changed" do
    cached_key = source_result_key(data_revision: "ops-rev-1", watermark: nil)
    current_key = source_result_key(data_revision: "ops-rev-2", watermark: nil)

    assert %SourceResultPreflight{status: :stale, reasons: reasons} =
             SourceResultPreflight.evaluate(
               cached_key,
               source_result(watermarks: []),
               current_key
             )

    assert :data_revision_changed in reasons
    refute :watermark_unknown in reasons
  end

  test "applies shared freshness semantics across watermarked and revision-backed sources" do
    watermarked_sources = [
      %{logical_source: :telemetry, data_source_id: "flight-questdb", binding_id: "flight-tlm"},
      %{
        logical_source: :limits,
        data_source_id: "limits-projection",
        binding_id: "flight-limits"
      }
    ]

    for source <- watermarked_sources do
      cached_key =
        source_result_key(
          logical_source: source.logical_source,
          data_source_id: source.data_source_id,
          source_binding_id: source.binding_id,
          complete_through: ~U[2026-06-17 12:00:00Z]
        )

      current_key =
        source_result_key(
          logical_source: source.logical_source,
          data_source_id: source.data_source_id,
          source_binding_id: source.binding_id,
          complete_through: ~U[2026-06-17 12:05:00Z]
        )

      assert %SourceResultPreflight{
               status: :stale,
               reasons: reasons,
               details: details
             } =
               SourceResultPreflight.evaluate(
                 cached_key,
                 source_result(
                   logical_source: source.logical_source,
                   data_source_id: source.data_source_id,
                   source_binding_id: source.binding_id
                 ),
                 current_key
               )

      assert :watermark_moved in reasons
      assert details.logical_source == source.logical_source
      assert details.data_source_id == source.data_source_id
      assert details.source_binding_id == source.binding_id
    end

    revision_backed_sources = [
      %{
        logical_source: :events,
        data_source_id: "events-projection",
        binding_id: "flight-events",
        data_revision: "events-rev-1",
        next_revision: "events-rev-2"
      },
      %{
        logical_source: :operational_observables,
        data_source_id: "ops-projection",
        binding_id: "flight-operational",
        data_revision: "ops-rev-1",
        next_revision: "ops-rev-2"
      }
    ]

    for source <- revision_backed_sources do
      cached_key =
        source_result_key(
          logical_source: source.logical_source,
          data_source_id: source.data_source_id,
          source_binding_id: source.binding_id,
          watermark: nil,
          data_revision: source.data_revision
        )

      current_key =
        source_result_key(
          logical_source: source.logical_source,
          data_source_id: source.data_source_id,
          source_binding_id: source.binding_id,
          watermark: nil,
          data_revision: source.data_revision
        )

      assert %SourceResultPreflight{status: :usable, reasons: [], details: details} =
               SourceResultPreflight.evaluate(
                 cached_key,
                 source_result(
                   logical_source: source.logical_source,
                   data_source_id: source.data_source_id,
                   source_binding_id: source.binding_id,
                   watermarks: []
                 ),
                 current_key
               )

      assert details.logical_source == source.logical_source
      assert details.data_source_id == source.data_source_id
      assert details.source_binding_id == source.binding_id

      changed_key =
        source_result_key(
          logical_source: source.logical_source,
          data_source_id: source.data_source_id,
          source_binding_id: source.binding_id,
          watermark: nil,
          data_revision: source.next_revision
        )

      assert %SourceResultPreflight{status: :stale, reasons: reasons} =
               SourceResultPreflight.evaluate(
                 cached_key,
                 source_result(
                   logical_source: source.logical_source,
                   data_source_id: source.data_source_id,
                   source_binding_id: source.binding_id,
                   watermarks: []
                 ),
                 changed_key
               )

      assert :data_revision_changed in reasons
      refute :watermark_unknown in reasons
    end
  end

  test "marks cache stale when current watermark freshness is unknown" do
    cached_key = source_result_key()

    current_key =
      source_result_key(watermark_confidence: :unknown, watermark_freshness_state: :unknown)

    assert %SourceResultPreflight{status: :stale, reasons: reasons} =
             SourceResultPreflight.evaluate(cached_key, source_result(), current_key)

    assert :freshness_unknown in reasons
  end

  test "marks cache stale when cached source result is already stale" do
    key = source_result_key()
    result = source_result(watermark_freshness_state: :stale)

    assert %SourceResultPreflight{status: :stale, reasons: [:freshness_stale]} =
             SourceResultPreflight.evaluate(key, result, key)
  end

  test "marks cache stale when current source health is degraded" do
    key = source_result_key()
    result = source_result()

    assert %SourceResultPreflight{status: :stale, reasons: reasons} =
             SourceResultPreflight.evaluate(key, result, key, source_health: :degraded)

    assert :source_degraded in reasons
  end

  test "treats snapshot cache entries as immutable despite freshness artifacts" do
    cached_key =
      source_result_key(
        cache_policy: :snapshot,
        complete_through: ~U[2026-06-17 12:00:00Z],
        freshness_policy: %{stale_after_ms: 5_000}
      )

    current_key =
      source_result_key(
        cache_policy: :snapshot,
        complete_through: ~U[2026-06-17 12:05:00Z],
        freshness_policy: %{stale_after_ms: 30_000}
      )

    cached_result = source_result(watermark_freshness_state: :stale)

    assert %SourceResultPreflight{
             status: :usable,
             reasons: [],
             details: %{cache_policy: :snapshot}
           } =
             SourceResultPreflight.evaluate(cached_key, cached_result, current_key,
               source_health: :degraded
             )
  end

  test "marks snapshot cache stale when request identity changes" do
    cached_key = source_result_key(cache_policy: :snapshot)

    current_key = source_result_key(cache_policy: :snapshot, to_time: ~U[2026-06-17 12:10:00Z])

    assert %SourceResultPreflight{status: :stale, reasons: reasons} =
             SourceResultPreflight.evaluate(cached_key, source_result(), current_key)

    assert :request_changed in reasons
  end

  defp source_result_key(opts \\ []) do
    logical_source = Keyword.get(opts, :logical_source, :telemetry)
    data_source_id = Keyword.get(opts, :data_source_id, "flight-questdb")
    binding_id = Keyword.get(opts, :source_binding_id, "flight-telemetry-binding")

    RuntimeCacheKey.source_result(source_request(opts),
      cache_policy: Keyword.get(opts, :cache_policy, :live),
      source_binding: source_binding(binding_id, data_source_id, logical_source),
      data_source: data_source(data_source_id, logical_source),
      freshness_policy: Keyword.get(opts, :freshness_policy, %{stale_after_ms: 5_000}),
      watermark:
        Keyword.get_lazy(opts, :watermark, fn ->
          source_watermark(data_source_id, binding_id, logical_source, opts)
        end),
      data_revision: Keyword.get(opts, :data_revision),
      correction_cursor: Keyword.get(opts, :correction_cursor),
      backfill_cursor: Keyword.get(opts, :backfill_cursor)
    )
  end

  defp source_request(opts) do
    %PlannedSourceRequest{
      request_id: "source_req_telemetry",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      logical_source: Keyword.get(opts, :logical_source, :telemetry),
      observables: ["battery_voltage"],
      time_context: %{
        mode: :archive,
        axis: :receipt_time,
        from: ~U[2026-06-17 12:00:00Z],
        to: Keyword.get(opts, :to_time, ~U[2026-06-17 12:05:00Z])
      },
      sampling: %{mode: :latest}
    }
  end

  defp source_result(opts \\ []) do
    logical_source = Keyword.get(opts, :logical_source, :telemetry)
    data_source_id = Keyword.get(opts, :data_source_id, "flight-questdb")
    binding_id = Keyword.get(opts, :source_binding_id, "flight-telemetry-binding")

    %SourceResult{
      request_id: "source_req_telemetry",
      watermarks:
        Keyword.get_lazy(opts, :watermarks, fn ->
          [source_watermark(data_source_id, binding_id, logical_source, opts)]
        end)
    }
  end

  defp source_binding(binding_id, data_source_id, logical_source) do
    %DataBinding{
      binding_id: binding_id,
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: :flight,
      logical_source: logical_source,
      data_source_id: data_source_id,
      dataset: dataset(logical_source)
    }
  end

  defp data_source(data_source_id, logical_source) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: adapter(logical_source),
      capabilities: %{latest?: true, range_scan?: true, watermarks?: true}
    }
  end

  defp source_watermark(data_source_id, binding_id, logical_source, opts) do
    complete_through = Keyword.get(opts, :complete_through, ~U[2026-06-17 12:00:00Z])

    %SourceWatermark{
      logical_source: logical_source,
      request_id: "source_req_telemetry",
      source_binding_id: binding_id,
      data_source_id: data_source_id,
      realm: :flight,
      dataset: dataset(logical_source),
      complete_through: complete_through,
      latest_receipt_time: complete_through,
      retention_starts_at: ~U[2026-06-17 11:00:00Z],
      confidence: Keyword.get(opts, :watermark_confidence, :best_effort),
      freshness_state: Keyword.get(opts, :watermark_freshness_state, :fresh)
    }
  end

  defp dataset(:telemetry), do: "flight"
  defp dataset(:limits), do: "telemetry_latest_limit_states"
  defp dataset(:events), do: "mission_events"
  defp dataset(:operational_observables), do: "operational_observables"

  defp adapter(:telemetry), do: Cadence.Dashboards.Sources.Telemetry
  defp adapter(:limits), do: Cadence.Dashboards.Sources.Limits
  defp adapter(:events), do: Cadence.Dashboards.Sources.Events
  defp adapter(:operational_observables), do: Cadence.Dashboards.Sources.OperationalObservables
end
