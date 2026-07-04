defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponents

  test "runtime_context_controls renders source binding and fallback state" do
    html =
      render_component(&DashboardRuntimeControlsComponents.runtime_context_controls/1,
        time_mode: "archive",
        time_from: "2026-06-17T12:00:00Z",
        time_to: "2026-06-17T12:05:00Z",
        replay_run_id: nil,
        time_validation: "reset",
        data_realm: "flight",
        data_realms: ["flight", "sim"],
        data_view: "canonical",
        compare_data_view: nil,
        data_source_id: "questdb-flight",
        source_binding_id: "flight-binding",
        data_bindings: [data_binding()],
        limit_mode: "observed",
        limit_mode_fallback: %{
          "requested_mode" => "projected",
          "applied_mode" => "observed",
          "reason" => "unsupported_limit_semantics_mode"
        },
        selected_data_ref: nil
      )

    document = LazyHTML.from_fragment(html)

    assert ["flight-binding"] =
             document
             |> LazyHTML.query(~s(#dashboard-source-binding option[value="flight-binding"]))
             |> LazyHTML.attribute("value")

    assert html =~ "flight-binding / questdb-flight"

    assert ["flight-binding"] =
             document
             |> LazyHTML.query("#dashboard-active-source")
             |> LazyHTML.attribute("data-dashboard-active-source-binding")

    assert ["projected"] =
             document
             |> LazyHTML.query("#dashboard-limit-mode-fallback")
             |> LazyHTML.attribute("data-requested-limit-mode")

    for limit_mode <- ["observed", "current", "recomputed", "compare"] do
      option =
        document
        |> LazyHTML.query(~s(#dashboard-limit-mode option[value="#{limit_mode}"]))

      assert [^limit_mode] = LazyHTML.attribute(option, "value")
      assert [] = LazyHTML.attribute(option, "disabled")
    end

    assert ["reset"] =
             document
             |> LazyHTML.query("#dashboard-time-validation")
             |> LazyHTML.attribute("data-time-validation")
  end

  test "runtime_context_controls renders replay selector, progress clock, and scrub command" do
    selected_timestamp_ms = DateTime.to_unix(~U[2026-06-17 12:02:00Z], :millisecond)

    html =
      render_component(&DashboardRuntimeControlsComponents.runtime_context_controls/1,
        time_mode: "replay_run",
        time_from: "2026-06-17T12:00:00Z",
        time_to: "2026-06-17T12:05:00Z",
        replay_run_id: "replay-run-1",
        time_validation: "ok",
        data_realm: "replay",
        data_realms: ["flight", "replay"],
        data_view: "as_recorded",
        compare_data_view: nil,
        data_source_id: "questdb-replay",
        source_binding_id: "replay-binding",
        data_bindings: [data_binding(), replay_binding()],
        replay_runs: [
          %{
            replay_run_id: "replay-run-1",
            status: :completed,
            replayed_sample_count: 42,
            started_at: ~U[2026-06-17 11:59:00Z],
            completed_at: ~U[2026-06-17 12:06:00Z]
          },
          %{
            replay_run_id: "replay-run-2",
            status: :running,
            replayed_sample_count: 7,
            started_at: ~U[2026-06-17 12:10:00Z],
            completed_at: nil
          }
        ],
        selected_replay_run: %{
          replay_run_id: "replay-run-1",
          status: :completed,
          replayed_sample_count: 42,
          started_at: ~U[2026-06-17 11:59:00Z],
          completed_at: ~U[2026-06-17 12:06:00Z]
        },
        limit_mode: "current",
        limit_mode_fallback: nil,
        selected_data_ref: %{"timestamp_ms" => selected_timestamp_ms}
      )

    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("#dashboard-replay-run-id")
             |> LazyHTML.attribute("value")

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query("#dashboard-replay-run-selector")
             |> LazyHTML.query("option[selected]")
             |> LazyHTML.attribute("value")

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-run-id")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-run-known")

    assert ["completed"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-run-status")

    assert ["2026-06-17T11:59:00Z"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-run-started-at")

    assert ["42"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-run-sample-count")

    assert ["2026-06-17T12:00:00Z"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-window-from")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-window-bounded")

    assert ["true"] =
             document
             |> LazyHTML.query("#dashboard-replay-scrub-to-selection")
             |> LazyHTML.attribute("data-dashboard-replay-scrub-available")

    assert [] =
             document
             |> LazyHTML.query("#dashboard-replay-scrub-to-selection")
             |> LazyHTML.attribute("disabled")

    assert [] =
             document
             |> LazyHTML.query("#dashboard-replay-metadata-warning")
             |> LazyHTML.attribute("id")
  end

  test "runtime_context_controls disables replay scrub when no timestamp is selected" do
    html =
      render_component(&DashboardRuntimeControlsComponents.runtime_context_controls/1,
        time_mode: "replay_run",
        time_from: nil,
        time_to: nil,
        replay_run_id: "replay-run-1",
        time_validation: "ok",
        data_realm: "replay",
        data_realms: ["flight", "replay"],
        data_view: "as_recorded",
        compare_data_view: nil,
        data_source_id: "questdb-replay",
        source_binding_id: "replay-binding",
        data_bindings: [data_binding(), replay_binding()],
        replay_runs: [],
        selected_replay_run: nil,
        limit_mode: "observed",
        limit_mode_fallback: nil,
        selected_data_ref: nil
      )

    document = LazyHTML.from_fragment(html)

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-replay-scrub-to-selection")
             |> LazyHTML.attribute("data-dashboard-replay-scrub-available")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-replay-scrub-to-selection")
             |> LazyHTML.attribute("disabled")

    assert ["false"] =
             document
             |> LazyHTML.query("#dashboard-replay-progress-clock")
             |> LazyHTML.attribute("data-dashboard-replay-window-bounded")
  end

  test "runtime_context_controls preserves unlisted replay deep links with metadata warning" do
    html =
      render_component(&DashboardRuntimeControlsComponents.runtime_context_controls/1,
        time_mode: "replay_run",
        time_from: "2026-06-17T12:00:00Z",
        time_to: "2026-06-17T12:05:00Z",
        replay_run_id: "replay-run-unlisted",
        time_validation: "ok",
        data_realm: "replay",
        data_realms: ["flight", "replay"],
        data_view: "as_recorded",
        compare_data_view: nil,
        data_source_id: "questdb-replay",
        source_binding_id: "replay-binding",
        data_bindings: [data_binding(), replay_binding()],
        replay_runs: [],
        selected_replay_run: nil,
        limit_mode: "observed",
        limit_mode_fallback: nil,
        selected_data_ref: %{
          "timestamp_ms" => DateTime.to_unix(~U[2026-06-17 12:02:00Z], :millisecond)
        }
      )

    document = LazyHTML.from_fragment(html)

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

  defp data_binding do
    %DataBinding{
      binding_id: "flight-binding",
      data_source_id: "questdb-flight",
      dataset: "flight",
      realm: :flight,
      logical_source: :telemetry,
      priority: 0,
      status: :active
    }
  end

  defp replay_binding do
    %DataBinding{
      binding_id: "replay-binding",
      data_source_id: "questdb-replay",
      dataset: "replay-run-1",
      realm: :replay,
      logical_source: :telemetry,
      priority: 0,
      status: :active
    }
  end
end
