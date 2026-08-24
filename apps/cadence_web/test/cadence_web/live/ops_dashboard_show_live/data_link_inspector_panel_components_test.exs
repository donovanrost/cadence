defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{DashboardAction, DataLink, Document}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents
  alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  test "data_link_panel renders inspector identity, rows, related links, and actions" do
    related_link = data_link(:telemetry_sample, "sample-1", "Telemetry sample")

    html =
      render_component(&DataLinkInspectorPanelComponents.data_link_panel/1,
        inspector: %{
          status: :context_only,
          status_text: "context_only",
          title: "Telemetry point",
          target: :telemetry_point,
          target_text: "telemetry point",
          target_id: "HK.counter",
          link_id: "telemetry_point:HK.counter:request-1",
          link_label: "Counter point",
          source: :frame,
          source_text: "frame",
          message: "Telemetry point is not present in the active operator point catalog.",
          rows: [%{label: "Point", value: "HK.counter"}],
          context_rows: [
            %{label: "Data realm", value: "flight"},
            %{label: "Data view", value: "all_revisions"},
            %{label: "Data source", value: "questdb-flight"},
            %{label: "Source binding", value: "binding-flight"},
            %{label: "Time mode", value: "replay_run"},
            %{label: "Time axis", value: "generation_time"},
            %{label: "Replay run", value: "replay-run-1"},
            %{label: "Scope", value: "spacecraft:single:sc-1"},
            %{label: "Limit mode", value: "operational"}
          ],
          related_links: [related_link],
          actions: [telemetry_explore_action()]
        },
        mission_id: "mission-1",
        dashboard_document: %Document{dashboard_id: "dashboard-1", name: "Dashboard"},
        dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"
      )

    document = LazyHTML.from_fragment(html)
    presentation = ViewTestSupport.data_link_inspector_presentation(html)

    assert ["telemetry_point"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-target")

    assert ["HK.counter"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-target-id")

    assert ["telemetry_point:HK.counter:request-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-link")

    assert ["all_revisions"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-data-view")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-source-binding-id")

    assert ["replay_run"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-time-mode")

    assert ["generation_time"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-time-axis")

    assert ["replay-run-1"] =
             document
             |> LazyHTML.query("#dashboard-data-link-inspector")
             |> LazyHTML.attribute("data-data-link-selected-replay-run-id")

    assert presentation["clipboard"]["button_id"] == "dashboard-data-link-copy-link"

    assert presentation["clipboard"]["clipboard_text"] ==
             "/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"

    assert presentation["clipboard"]["button_class"] ==
             "btn btn-sm btn-outline w-full justify-start"

    assert presentation["clipboard"]["icon"] == "hero-link"
    assert presentation["clipboard"]["icon_class"] == "h-4 w-4"
    assert presentation["clipboard"]["label"] == "Copy link"

    assert "context_only" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("selection", "State")
             |> get_in(["value", "text"])

    assert "telemetry point" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("selection", "Target")
             |> get_in(["value", "text"])

    assert "telemetry_point:HK.counter:request-1" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("selection", "Link")
             |> get_in(["value", "text"])

    assert "all_revisions" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("selection", "Data view")
             |> get_in(["value", "text"])

    assert "replay_run" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("selection", "Time mode")
             |> get_in(["value", "text"])

    assert "replay-run-1" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("selection", "Replay run")
             |> get_in(["value", "text"])

    assert "HK.counter" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("record", "Point")
             |> get_in(["value", "text"])

    assert "questdb-flight" =
             presentation
             |> ViewTestSupport.data_link_inspector_row("runtime_context", "Data source")
             |> get_in(["value", "text"])

    assert [related] = get_in(presentation, ["related", "groups", Access.at(0), "links"])
    assert related["attrs"]["data-data-link-related-target"] == "telemetry sample"

    assert related["attrs"]["phx-value-data-source-id"] == "questdb-flight"

    assert related["attrs"]["phx-value-source-binding-id"] == "binding-flight"

    assert related["attrs"]["phx-value-nav-from-target"] == "telemetry_point"

    assert related["attrs"]["phx-value-nav-from-target-id"] == "HK.counter"

    assert [%{"target_id" => "HK.counter"}] =
             related["attrs"]["phx-value-nav-trail"]
             |> Jason.decode!()

    assert [action] = presentation["actions"]
    assert action["attrs"]["data-dashboard-action-source"] == "data_link_panel"
    assert action["attrs"]["data-phx-link"] == "redirect"
    assert action["attrs"]["data-phx-link-state"] == "push"

    explore_href = action["attrs"]["href"]

    assert explore_href =~ "/missions/mission-1/ops/explore"
    assert explore_href =~ "point_id=HK.counter"
    assert explore_href =~ "source_dashboard_id=dashboard-1"
  end

  defp data_link(target, target_id, label, opts \\ []) do
    %DataLink{
      link_id: "#{target}:#{target_id}:request-1",
      label: label,
      target: target,
      target_id: target_id,
      relationship_kind: Keyword.get(opts, :relationship_kind),
      source: :frame,
      context: %{
        data: %{
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight"
        },
        time: %{
          mode: "archive",
          axis: "receipt_time"
        }
      }
    }
  end

  defp telemetry_explore_action do
    %DashboardAction{
      action_id: "explore",
      label: "Explore telemetry",
      target: :telemetry_explore,
      kind: :invoke,
      query: %{
        "point_id" => "HK.counter",
        "sample_id" => "sample-1",
        "realm" => "flight",
        "data_source_id" => "questdb-flight",
        "source_binding_id" => "binding-flight"
      },
      source: :frame
    }
  end
end
