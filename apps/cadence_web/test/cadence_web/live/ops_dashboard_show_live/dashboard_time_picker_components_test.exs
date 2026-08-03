defmodule CadenceWeb.OpsDashboardShowLive.DashboardTimePickerComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.DashboardTimePickerComponents

  defp render_cluster(overrides) do
    attrs =
      Keyword.merge(
        [
          time_mode: "live",
          time_axis: "generation_time",
          time_from: nil,
          time_to: nil,
          replay_run_id: nil,
          time_validation: "ok",
          data_realm: "flight",
          data_view: "canonical",
          compare_data_view: nil,
          source_binding_id: nil,
          limit_mode: "observed",
          replay_runs: [],
          selected_replay_run: nil,
          selected_data_ref: nil,
          quick_query: "",
          recent_ranges: []
        ],
        overrides
      )

    render_component(&DashboardTimePickerComponents.time_toolbar_cluster/1, attrs)
  end

  test "plain live mode renders Live label with disabled shift and zoom" do
    document = LazyHTML.from_fragment(render_cluster([]))

    assert ["live"] =
             document
             |> LazyHTML.query("#dashboard-active-time-range")
             |> LazyHTML.attribute("data-dashboard-time-mode")

    assert document |> LazyHTML.query("#dashboard-active-time-range") |> LazyHTML.text() =~ "Live"

    for id <- [
          "dashboard-time-shift-back",
          "dashboard-time-shift-forward",
          "dashboard-time-zoom-out"
        ] do
      assert [""] = document |> LazyHTML.query("##{id}") |> LazyHTML.attribute("disabled")
    end

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-refresh-interval")
             |> LazyHTML.attribute("disabled")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-time-preset-live")
             |> LazyHTML.attribute("disabled")
  end

  test "sliding window labels the trigger and highlights the quick range" do
    document =
      LazyHTML.from_fragment(render_cluster(time_from: "now-6h", time_to: "now"))

    assert document |> LazyHTML.query("#dashboard-active-time-range") |> LazyHTML.text() =~
             "Last 6 hours"

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-time-preset-last-6h")
             |> LazyHTML.attribute("aria-current")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-time-preset-last-5m")
             |> LazyHTML.attribute("aria-current")

    for id <- [
          "dashboard-time-shift-back",
          "dashboard-time-shift-forward",
          "dashboard-time-zoom-out"
        ] do
      assert [] = document |> LazyHTML.query("##{id}") |> LazyHTML.attribute("disabled")
    end

    assert [] =
             document
             |> LazyHTML.query("#dashboard-time-preset-live")
             |> LazyHTML.attribute("disabled")
  end

  test "renders every quick range and filters by search query" do
    document = LazyHTML.from_fragment(render_cluster([]))

    assert document
           |> LazyHTML.query("#dashboard-time-presets button")
           |> LazyHTML.attribute("id")
           |> length() == 9

    filtered = LazyHTML.from_fragment(render_cluster(quick_query: "6 h"))

    assert ["dashboard-time-preset-last-6h"] =
             filtered
             |> LazyHTML.query("#dashboard-time-presets button")
             |> LazyHTML.attribute("id")
  end

  test "archive mode renders the time validation badge and range form values" do
    document =
      LazyHTML.from_fragment(
        render_cluster(
          time_mode: "archive",
          time_from: "2026-06-17T12:00:00Z",
          time_to: "2026-06-17T12:05:00Z",
          time_validation: "reset"
        )
      )

    assert ["reset"] =
             document
             |> LazyHTML.query("#dashboard-time-validation")
             |> LazyHTML.attribute("data-time-validation")

    assert ["2026-06-17T12:00:00Z"] =
             document |> LazyHTML.query("#dashboard-time-from") |> LazyHTML.attribute("value")

    assert ["2026-06-17T12:05:00Z"] =
             document |> LazyHTML.query("#dashboard-time-to") |> LazyHTML.attribute("value")
  end

  test "renders recently used ranges with an empty state fallback" do
    empty = LazyHTML.from_fragment(render_cluster([]))

    assert empty |> LazyHTML.query("#dashboard-time-recents") |> LazyHTML.text() =~
             "Apply an absolute range"

    document =
      LazyHTML.from_fragment(
        render_cluster(
          recent_ranges: [%{from: "2026-06-17T12:00:00Z", to: "2026-06-17T12:05:00Z"}]
        )
      )

    assert ["2026-06-17T12:00:00Z"] =
             document
             |> LazyHTML.query("#dashboard-time-recents button[data-dashboard-time-recent-range]")
             |> LazyHTML.attribute("phx-value-from")
  end

  test "renders replay selector, progress clock, and scrub command" do
    selected_timestamp_ms = DateTime.to_unix(~U[2026-06-17 12:02:00Z], :millisecond)

    replay_run = %{
      replay_run_id: "replay-run-1",
      status: :completed,
      replayed_sample_count: 42,
      started_at: ~U[2026-06-17 11:59:00Z],
      completed_at: ~U[2026-06-17 12:06:00Z]
    }

    document =
      LazyHTML.from_fragment(
        render_cluster(
          time_mode: "replay_run",
          time_from: "2026-06-17T12:00:00Z",
          time_to: "2026-06-17T12:05:00Z",
          replay_run_id: "replay-run-1",
          data_realm: "replay",
          data_view: "as_recorded",
          source_binding_id: "replay-binding",
          limit_mode: "current",
          replay_runs: [
            replay_run,
            %{
              replay_run_id: "replay-run-2",
              status: :running,
              replayed_sample_count: 7,
              started_at: ~U[2026-06-17 12:10:00Z],
              completed_at: nil
            }
          ],
          selected_replay_run: replay_run,
          selected_data_ref: %{"timestamp_ms" => selected_timestamp_ms}
        )
      )

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query("#dashboard-replay-run-selector option[selected]")
             |> LazyHTML.attribute("value")

    clock = LazyHTML.query(document, "#dashboard-replay-progress-clock")
    assert ["replay-run-1"] = LazyHTML.attribute(clock, "data-dashboard-replay-run-id")
    assert ["true"] = LazyHTML.attribute(clock, "data-dashboard-replay-run-known")
    assert ["completed"] = LazyHTML.attribute(clock, "data-dashboard-replay-run-status")

    assert ["2026-06-17T11:59:00Z"] =
             LazyHTML.attribute(clock, "data-dashboard-replay-run-started-at")

    assert ["42"] = LazyHTML.attribute(clock, "data-dashboard-replay-run-sample-count")

    assert ["2026-06-17T12:00:00Z"] =
             LazyHTML.attribute(clock, "data-dashboard-replay-window-from")

    assert ["true"] = LazyHTML.attribute(clock, "data-dashboard-replay-window-bounded")

    scrub = LazyHTML.query(document, "#dashboard-replay-scrub-to-selection")
    assert ["true"] = LazyHTML.attribute(scrub, "data-dashboard-replay-scrub-available")
    assert [] = LazyHTML.attribute(scrub, "disabled")

    assert [] =
             document
             |> LazyHTML.query("#dashboard-replay-metadata-warning")
             |> LazyHTML.attribute("id")

    assert document |> LazyHTML.query("#dashboard-active-time-range") |> LazyHTML.text() =~
             "Replay · replay-run-1"

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-time-shift-back")
             |> LazyHTML.attribute("disabled")
  end

  test "disables replay scrub when no timestamp is selected" do
    document =
      LazyHTML.from_fragment(
        render_cluster(
          time_mode: "replay_run",
          replay_run_id: "replay-run-1",
          data_realm: "replay",
          data_view: "as_recorded"
        )
      )

    scrub = LazyHTML.query(document, "#dashboard-replay-scrub-to-selection")
    assert ["false"] = LazyHTML.attribute(scrub, "data-dashboard-replay-scrub-available")
    assert [""] = LazyHTML.attribute(scrub, "disabled")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-window-bounded")
  end

  test "preserves unlisted replay deep links with metadata warning" do
    document =
      LazyHTML.from_fragment(
        render_cluster(
          time_mode: "replay_run",
          time_from: "2026-06-17T12:00:00Z",
          time_to: "2026-06-17T12:05:00Z",
          replay_run_id: "replay-run-unlisted",
          data_realm: "replay",
          data_view: "as_recorded",
          selected_data_ref: %{
            "timestamp_ms" => DateTime.to_unix(~U[2026-06-17 12:02:00Z], :millisecond)
          }
        )
      )

    assert ["replay-run-unlisted"] =
             document
             |> LazyHTML.query("#dashboard-replay-run-selector option[selected]")
             |> LazyHTML.attribute("value")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-run-known")

    assert ["replay-run-unlisted"] =
             document
             |> LazyHTML.query("#dashboard-replay-metadata-warning")
             |> LazyHTML.attribute("data-dashboard-replay-run-id")
  end
end
