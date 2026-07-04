defmodule Cadence.Dashboards.RuntimeInvalidation.EventTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.RuntimeInvalidation.Event

  test "normalizes event measurements and telemetry metadata" do
    occurred_at = DateTime.from_unix!(1_700_000_000, :second)

    event =
      Event.new(
        :source_watermark_changed,
        [:source_result, :frame],
        %{logical_source: :telemetry, data_source_id: "source-1"},
        %{source_result: %{logical_source: :telemetry}, frame: %{logical_source: :telemetry}},
        %{source_results: 2, frames: 3},
        occurred_at: occurred_at
      )

    assert event.domain_fact == :source_watermark_changed
    assert event.measurements.plans == 0
    assert event.measurements.source_results == 2
    assert event.measurements.frames == 3
    assert event.measurements.total == 5
    assert event.occurred_at == occurred_at

    metadata = Event.to_telemetry_metadata(event, :runtime_cache)

    assert metadata.boundary == :source_watermark_changed
    assert metadata.filters.data_source_id == "source-1"
    assert metadata.layer_filters.frame.logical_source == :telemetry
    assert metadata.measurements.total == 5
    assert metadata.runtime_cache == :runtime_cache
  end

  test "builds typed events from telemetry metadata" do
    occurred_at = DateTime.from_unix!(1_700_000_100, :second)

    assert {:ok, event} =
             Event.from_metadata(
               %{
                 "boundary" => "source_watermark_changed",
                 "domain_fact" => "source_watermark_changed",
                 "layers" => ["source_result", "frame"],
                 "filters" => %{"mission_id" => "mission-1"},
                 "layer_filters" => %{"source_result" => %{"mission_id" => "mission-1"}}
               },
               %{"source_results" => 1, "frames" => 1},
               occurred_at: occurred_at
             )

    assert event.boundary == :source_watermark_changed
    assert event.domain_fact == :source_watermark_changed
    assert event.layers == [:source_result, :frame]
    assert event.filters == %{"mission_id" => "mission-1"}
    assert event.layer_filters == %{source_result: %{"mission_id" => "mission-1"}}
    assert event.measurements.source_results == 1
    assert event.measurements.frames == 1
    assert event.measurements.total == 2
    assert event.occurred_at == occurred_at
  end

  test "builds typed events from runtime health recent events" do
    observed_at = DateTime.from_unix!(1_700_000_200, :second)

    assert {:ok, event} =
             Event.from_recent_event(%{
               source: :dashboards_runtime_invalidation,
               observed_at: observed_at,
               metadata: %{
                 boundary: :historical_data_changed,
                 layers: [:source_result, :frame],
                 filters: %{mission_id: "mission-1"}
               },
               measurements: %{total: 3}
             })

    assert event.boundary == :historical_data_changed
    assert event.occurred_at == observed_at
    assert event.measurements.total == 3
  end

  test "normalizes every runtime invalidation coverage boundary from telemetry metadata" do
    for row <- RuntimeInvalidation.coverage_matrix() do
      assert {:ok, event} =
               Event.from_metadata(
                 %{
                   boundary: Atom.to_string(row.boundary),
                   domain_fact: Atom.to_string(row.domain_fact),
                   layers: Enum.map(row.layers, &Atom.to_string/1),
                   filters: %{mission_id: "mission-1"}
                 },
                 %{total: 1}
               )

      assert event.boundary == row.boundary
      assert event.domain_fact == row.domain_fact
      assert event.layers == row.layers
    end
  end

  test "classifies refresh action for every runtime invalidation coverage boundary" do
    expected_actions = %{
      dashboard_version_changed: :refresh_plan,
      catalog_revision_changed: :refresh_plan,
      limit_definition_changed: :refresh_source_result,
      data_source_binding_changed: :refresh_plan,
      source_watermark_changed: :refresh_source_result,
      historical_data_changed: :refresh_source_result,
      telemetry_revision_state_changed: :refresh_source_result,
      source_health_changed: :refresh_source_result,
      events_changed: :refresh_source_result
    }

    for row <- RuntimeInvalidation.coverage_matrix() do
      event =
        Event.new(
          row.boundary,
          row.layers,
          %{mission_id: "mission-1"},
          %{},
          %{total: 1}
        )

      assert Event.refresh_action(event) == Map.fetch!(expected_actions, row.boundary)
    end
  end

  test "classifies degraded source health invalidations as wait actions" do
    event =
      Event.new(
        :source_health_changed,
        [:source_result, :frame],
        %{source_health: "degraded"},
        %{},
        %{total: 1}
      )

    assert Event.refresh_action(event) == :wait_for_source_health
  end
end
