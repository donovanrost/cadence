defmodule Cadence.Dashboards.DataLinkInspectorTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{DashboardAction, DataLink, DataLinkInspector}

  test "normalizes serialized inspector payloads into a typed contract" do
    inspector =
      DataLinkInspector.new(%{
        "status" => "resolved",
        "title" => "Telemetry sample",
        "message" => "Loaded",
        "target" => "telemetry-sample",
        "target_text" => "telemetry sample",
        "target_id" => "sample-1",
        "link_id" => "link-1",
        "link_label" => "Sample link",
        "source" => "warning",
        "source_text" => "warning",
        "source_context" => %{"realm" => "flight"},
        "rows" => [%{"label" => "Sample", "value" => 1}, "not a row"],
        "context_rows" => [%{label: :Realm, value: :flight}],
        "navigation" => %{"from" => %{"target_id" => "source-event-1"}},
        "related_links" => [
          %{
            "link_id" => "related-1",
            "target" => "telemetry_point",
            "target_id" => "HK.counter"
          },
          "not a link"
        ],
        "actions" => [
          %{
            "action_id" => "explore",
            "target" => "telemetry_explore",
            "kind" => "invoke"
          },
          "not an action"
        ]
      })

    assert %DataLinkInspector{
             status: :resolved,
             status_text: "resolved",
             title: "Telemetry sample",
             message: "Loaded",
             target: :telemetry_sample,
             target_text: "telemetry sample",
             target_id: "sample-1",
             link_id: "link-1",
             link_label: "Sample link",
             source: :warning,
             source_text: "warning",
             source_context: %{"realm" => "flight"},
             rows: [%{label: "Sample", value: "1"}],
             context_rows: [%{label: "Realm", value: "flight"}],
             navigation: %{"from" => %{"target_id" => "source-event-1"}},
             related_links: [%DataLink{target: :telemetry_point, target_id: "HK.counter"}],
             actions: [%DashboardAction{target: :telemetry_explore, kind: :invoke}]
           } = inspector
  end

  test "defaults invalid optional collections to empty contract fields" do
    assert %DataLinkInspector{
             status: :missing,
             status_text: "missing",
             source_context: %{},
             rows: [],
             context_rows: [],
             navigation: nil,
             related_links: [],
             actions: []
           } =
             DataLinkInspector.new(%{
               status: "unknown",
               rows: "bad",
               context_rows: nil,
               navigation: [],
               related_links: nil,
               actions: nil
             })
  end
end
