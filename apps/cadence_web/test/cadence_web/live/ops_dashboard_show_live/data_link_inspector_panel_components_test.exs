defmodule CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{DashboardAction, DataLink, Document}
  alias CadenceWeb.OpsDashboardShowLive.DataLinkInspectorPanelComponents

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

    assert ["/missions/mission-1/ops/dashboards/dashboard-1?panel=data_link"] =
             document
             |> LazyHTML.query("#dashboard-data-link-copy-link")
             |> LazyHTML.attribute("data-clipboard-text")

    assert "context_only" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="State"]))
             |> selected_text()

    assert "telemetry point" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Target"]))
             |> selected_text()

    assert "telemetry_point:HK.counter:request-1" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Link"]))
             |> selected_text()

    assert "all_revisions" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Data view"]))
             |> selected_text()

    assert "replay_run" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Time mode"]))
             |> selected_text()

    assert "replay-run-1" =
             document
             |> LazyHTML.query(~s([data-data-link-selection-field="Replay run"]))
             |> selected_text()

    assert "HK.counter" =
             document
             |> LazyHTML.query(~s([data-data-link-field="Point"]))
             |> selected_text()

    assert "questdb-flight" =
             document
             |> LazyHTML.query(~s([data-data-link-context="Data source"]))
             |> selected_text()

    assert ["telemetry sample"] =
             document
             |> LazyHTML.query("[data-data-link-related-target]")
             |> LazyHTML.attribute("data-data-link-related-target")

    assert ["questdb-flight"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-data-source-id")

    assert ["binding-flight"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-source-binding-id")

    assert ["telemetry_point"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-nav-from-target")

    assert ["HK.counter"] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-nav-from-target-id")

    assert [%{"target_id" => "HK.counter"}] =
             document
             |> LazyHTML.query("[data-data-link-related-ref]")
             |> LazyHTML.attribute("phx-value-nav-trail")
             |> List.first()
             |> Jason.decode!()

    assert ["data_link_panel"] =
             document
             |> LazyHTML.query("#dashboard-data-link-explore")
             |> LazyHTML.attribute("data-dashboard-action-source")

    assert [explore_href] =
             document
             |> LazyHTML.query("#dashboard-data-link-explore")
             |> LazyHTML.attribute("href")

    assert explore_href =~ "/missions/mission-1/ops/telemetry/explore"
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

  defp selected_text(lazy_html) do
    lazy_html
    |> LazyHTML.text()
    |> String.trim()
  end
end
