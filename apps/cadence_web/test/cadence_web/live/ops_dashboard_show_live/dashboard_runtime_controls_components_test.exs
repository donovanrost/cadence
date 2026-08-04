defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.DataSources.DataBinding
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
  end

  test "runtime_context_controls renders marker toggles reflecting hidden categories" do
    html =
      render_component(&DashboardRuntimeControlsComponents.runtime_context_controls/1,
        time_mode: "live",
        time_from: nil,
        time_to: nil,
        replay_run_id: nil,
        time_validation: "ok",
        data_realm: "flight",
        data_realms: ["flight"],
        data_view: "canonical",
        compare_data_view: nil,
        data_source_id: nil,
        source_binding_id: nil,
        data_bindings: [data_binding()],
        limit_mode: "observed",
        limit_mode_fallback: nil,
        hidden_marker_categories: ["contacts"],
        selected_data_ref: nil
      )

    document = LazyHTML.from_fragment(html)

    assert ["markers[contacts]"] =
             document
             |> LazyHTML.query("#dashboard-marker-contacts")
             |> LazyHTML.attribute("name")

    assert [] =
             document
             |> LazyHTML.query("#dashboard-marker-contacts")
             |> LazyHTML.attribute("checked")

    assert [""] =
             document
             |> LazyHTML.query("#dashboard-marker-limits")
             |> LazyHTML.attribute("checked")

    assert document |> LazyHTML.query("#dashboard-markers-hidden-count") |> LazyHTML.text() =~
             "1 hidden"

    for key <- [
          "limits",
          "contacts",
          "source_status",
          "watermarks",
          "mission_events",
          "data_management"
        ] do
      assert [_id] =
               document
               |> LazyHTML.query("#dashboard-marker-#{key}")
               |> LazyHTML.attribute("id")
    end
  end

  test "runtime_context_controls carries the replay run id in the data form" do
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
        replay_runs: [],
        selected_replay_run: nil,
        limit_mode: "current",
        limit_mode_fallback: nil,
        selected_data_ref: nil
      )

    document = LazyHTML.from_fragment(html)

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query("#dashboard-replay-run-id")
             |> LazyHTML.attribute("value")
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
