defmodule CadenceWeb.OpsDashboardShowLive.WidgetWarningComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetWarningComponents

  test "engine_warning_badge renders evidence controls and detail evidence rows" do
    html =
      render_component(&WidgetWarningComponents.engine_warning_badge/1,
        warning: warning(),
        placement_id: "placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["source_degraded"] =
             document
             |> LazyHTML.query(~s(summary[data-engine-warning="source_degraded"]))
             |> LazyHTML.attribute("data-engine-warning")

    assert ["open_evidence"] =
             document
             |> LazyHTML.query("[data-warning-evidence-open]")
             |> LazyHTML.attribute("phx-click")

    assert ["warning"] =
             document
             |> LazyHTML.query("[data-warning-evidence-open]")
             |> LazyHTML.attribute("phx-value-kind")

    assert ["placement-1"] =
             document
             |> LazyHTML.query("[data-warning-evidence-open]")
             |> LazyHTML.attribute("phx-value-placement-id")

    assert ["source_degraded"] =
             document
             |> LazyHTML.query("[data-warning-evidence-open]")
             |> LazyHTML.attribute("phx-value-warning-code")

    assert ["request-1"] =
             document
             |> LazyHTML.query("[data-warning-evidence-open]")
             |> LazyHTML.attribute("phx-value-source-request-id")

    assert ["Source request"] =
             document
             |> LazyHTML.query(~s([data-warning-detail="Source request"]))
             |> LazyHTML.attribute("data-warning-detail")

    assert "request-1" =
             document
             |> LazyHTML.query(~s([data-warning-detail="Source request"]))
             |> LazyHTML.text()
             |> String.trim()

    assert ["source", "frame"] =
             document
             |> LazyHTML.query("[data-warning-evidence-kind]")
             |> LazyHTML.attribute("data-warning-evidence-kind")
  end

  test "engine_warning_badge renders warning data links with context fallback" do
    html =
      render_component(&WidgetWarningComponents.engine_warning_badge/1,
        warning:
          warning(%{
            links: [
              %{
                link_id: "warning-link-1",
                target_text: "telemetry_sample",
                target_id: "sample-1",
                source_text: "telemetry",
                context: %{
                  data: %{
                    realm: :simulation,
                    view: "all_revisions",
                    data_source_id: "questdb-sim",
                    source_binding_id: "binding-sim"
                  },
                  time: %{mode: :replay_run, axis: "generation_time"}
                }
              },
              %{
                link_id: "warning-link-2",
                target_text: "telemetry_frame",
                target_id: "frame-1",
                source_text: "telemetry"
              }
            ]
          }),
        placement_id: "placement-1"
      )

    document = LazyHTML.from_fragment(html)

    assert ["open_data_link", "open_data_link"] =
             document
             |> LazyHTML.query("[data-warning-link-ref]")
             |> LazyHTML.attribute("phx-click")

    assert ["warning-link-1", "warning-link-2"] =
             document
             |> LazyHTML.query("[data-warning-link-ref]")
             |> LazyHTML.attribute("phx-value-link-id")

    assert ["simulation", "flight"] =
             document
             |> LazyHTML.query("[data-warning-link-ref]")
             |> LazyHTML.attribute("phx-value-realm")

    assert ["all_revisions", "canonical"] =
             document
             |> LazyHTML.query("[data-warning-link-ref]")
             |> LazyHTML.attribute("phx-value-data-view")

    assert ["replay_run", "wall_clock"] =
             document
             |> LazyHTML.query("[data-warning-link-ref]")
             |> LazyHTML.attribute("phx-value-time-mode")
  end

  test "warning_codes joins warning code text values" do
    assert WidgetWarningComponents.warning_codes([
             %{code_text: "source_degraded"},
             %{code_text: "late_arrival"}
           ]) == "source_degraded,late_arrival"

    assert WidgetWarningComponents.warning_codes(nil) == ""
  end

  defp warning(attrs \\ %{}) do
    Map.merge(
      %{
        code_text: "source_degraded",
        label: "Source degraded",
        message: "Telemetry source returned degraded data.",
        severity: :warning,
        details: %{
          source_request_id: "request-1",
          logical_source: "simulator",
          realm: "flight",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight",
          data_view: "canonical",
          time_mode: "wall_clock",
          time_axis: "receipt_time",
          replay_run_id: "replay-1"
        },
        detail_rows: [
          %{label: "Source request", value: "request-1"}
        ],
        evidence: [
          %{
            kind_text: "source",
            id: "request-1",
            source_text: "simulator",
            observed_at_text: "2026-06-17T12:00:00Z"
          },
          %{
            kind_text: "frame",
            id: "frame-1",
            source_text: "telemetry",
            observed_at_text: "2026-06-17T12:00:01Z"
          }
        ],
        links: []
      },
      attrs
    )
  end
end
