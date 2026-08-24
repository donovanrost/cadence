defmodule CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivityComponentsTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivityComponents

  test "event_details renders captured health snapshot metadata" do
    snapshot = %{
      "schema" => "dashboard_health_snapshot.v1",
      "snapshot_id" => "health-snapshot-1",
      "state" => "attention",
      "severity" => "warning",
      "counts" => %{
        "widgets" => 6,
        "ready" => 2,
        "affected" => 4,
        "blocked" => 1,
        "stale" => 2,
        "degraded" => 1
      },
      "placement_ids" => %{
        "affected" => ["placement-1", "placement-2"],
        "blocked" => ["placement-3"],
        "stale" => ["placement-4"],
        "degraded" => ["placement-5"]
      }
    }

    event =
      lifecycle_event(
        "dashboard-lifecycle-event-health",
        :health_snapshot_captured,
        payload: %{
          "schema" => "dashboard_health_snapshot_capture.v1",
          "source" => "operator",
          "snapshot_id" => "health-snapshot-1",
          "snapshot_schema" => "dashboard_health_snapshot.v1",
          "health_state" => "attention",
          "health_severity" => "warning",
          "captured_reason" => "pre-pass review",
          "snapshot" => snapshot
        }
      )

    html = render_component(&HealthSnapshotActivityComponents.event_details/1, event: event)

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-health-snapshot-event-dashboard-lifecycle-event-health-component"
      )

    assert vue.component == "HealthSnapshotActivity"

    assert vue.id ==
             "dashboard-health-snapshot-event-dashboard-lifecycle-event-health-component"

    assert vue.class == "contents"
    refute vue.ssr
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]

    assert presentation |> Map.keys() |> Enum.sort() ==
             ~w(copy_host copy_props counts placements root summary)

    root = presentation["root"]

    assert root["class"] ==
             "mt-3 space-y-3 border-t border-base-300/70 pt-3 text-xs"

    refute Map.has_key?(root, "id")
    assert root["attrs"]["data-dashboard-health-snapshot-id"] == "health-snapshot-1"

    assert root["attrs"]["data-dashboard-health-snapshot-schema"] ==
             "dashboard_health_snapshot.v1"

    assert root["attrs"]["data-dashboard-health-snapshot-state"] == "attention"

    assert root["attrs"] == %{
             "data-dashboard-health-snapshot-capture-schema" =>
               "dashboard_health_snapshot_capture.v1",
             "data-dashboard-health-snapshot-event" => "dashboard-lifecycle-event-health",
             "data-dashboard-health-snapshot-id" => "health-snapshot-1",
             "data-dashboard-health-snapshot-reason" => "pre-pass review",
             "data-dashboard-health-snapshot-schema" => "dashboard_health_snapshot.v1",
             "data-dashboard-health-snapshot-severity" => "warning",
             "data-dashboard-health-snapshot-source" => "operator",
             "data-dashboard-health-snapshot-state" => "attention"
           }

    assert presentation["summary"]["class"] == "flex items-start justify-between gap-2"

    assert presentation["summary"]["rows_class"] ==
             "grid min-w-0 grid-cols-[5rem_1fr] gap-x-2 gap-y-1"

    assert Enum.map(presentation["summary"]["rows"], & &1["order"]) == [0, 1, 2]

    assert Enum.map(presentation["summary"]["rows"], & &1["label"]["text"]) ==
             ["Snapshot", "State", "Severity"]

    assert Enum.map(presentation["summary"]["rows"], & &1["value"]["text"]) ==
             ["health-snapshot-1", "attention", "warning"]

    assert Enum.map(presentation["summary"]["rows"], & &1["label"]["class"]) ==
             ["hud-label", "hud-label", "hud-label"]

    assert Enum.map(presentation["summary"]["rows"], & &1["value"]["class"]) == [
             "truncate font-mono text-base-content/70",
             "font-mono text-base-content/70",
             "font-mono text-base-content/70"
           ]

    assert Enum.map(
             presentation["summary"]["rows"],
             & &1["value"]["attrs"]["data-activity-field"]
           ) == ["Health snapshot", "Health state", "Health severity"]

    assert Enum.map(
             presentation["counts"]["rows"],
             & &1["attrs"]["data-dashboard-health-snapshot-count"]
           ) == ["widgets", "ready", "affected", "blocked", "stale", "degraded"]

    assert Enum.map(
             presentation["counts"]["rows"],
             & &1["attrs"]["data-dashboard-health-snapshot-count-value"]
           ) == ["6", "2", "4", "1", "2", "1"]

    assert Enum.map(presentation["counts"]["rows"], & &1["order"]) == [0, 1, 2, 3, 4, 5]
    assert presentation["counts"]["class"] == "grid grid-cols-2 gap-2"

    assert Enum.map(presentation["counts"]["rows"], & &1["class"]) ==
             List.duplicate("border border-base-300/70 bg-base-100/50 px-2 py-1.5", 6)

    assert Enum.map(presentation["counts"]["rows"], & &1["label"]) == [
             %{"class" => "hud-label", "text" => "Widgets"},
             %{"class" => "hud-label", "text" => "Ready"},
             %{"class" => "hud-label", "text" => "Affected"},
             %{"class" => "hud-label", "text" => "Blocked"},
             %{"class" => "hud-label", "text" => "Stale"},
             %{"class" => "hud-label", "text" => "Degraded"}
           ]

    assert Enum.map(presentation["counts"]["rows"], & &1["value"]) == [
             %{"class" => "font-mono text-base-content/80", "text" => "6"},
             %{"class" => "font-mono text-base-content/80", "text" => "2"},
             %{"class" => "font-mono text-base-content/80", "text" => "4"},
             %{"class" => "font-mono text-base-content/80", "text" => "1"},
             %{"class" => "font-mono text-base-content/80", "text" => "2"},
             %{"class" => "font-mono text-base-content/80", "text" => "1"}
           ]

    assert Enum.map(
             presentation["placements"]["rows"],
             & &1["value"]["attrs"]["data-dashboard-health-snapshot-placements"]
           ) == ["affected", "blocked", "stale", "degraded"]

    assert Enum.map(
             presentation["placements"]["rows"],
             & &1["value"]["attrs"]["data-dashboard-health-snapshot-placement-ids"]
           ) == ["placement-1,placement-2", "placement-3", "placement-4", "placement-5"]

    assert Enum.map(presentation["placements"]["rows"], & &1["value"]["text"]) ==
             ["placement-1, placement-2", "placement-3", "placement-4", "placement-5"]

    assert Enum.map(presentation["placements"]["rows"], & &1["label"]) == [
             %{"class" => "hud-label", "text" => "Affected"},
             %{"class" => "hud-label", "text" => "Blocked"},
             %{"class" => "hud-label", "text" => "Stale"},
             %{"class" => "hud-label", "text" => "Degraded"}
           ]

    assert Enum.map(presentation["placements"]["rows"], & &1["value"]["class"]) ==
             List.duplicate("font-mono text-base-content/70", 4)

    assert Enum.map(presentation["placements"]["rows"], & &1["order"]) == [0, 1, 2, 3]
    assert presentation["placements"]["visible"]

    assert presentation["placements"]["class"] ==
             "grid grid-cols-[5rem_1fr] gap-x-2 gap-y-1"

    copy_host = presentation["copy_host"]
    copy = presentation["copy_props"]

    assert copy_host == %{
             "class" => "contents",
             "id" =>
               "dashboard-health-snapshot-event-copy-dashboard-lifecycle-event-health-component"
           }

    assert copy["button_id"] ==
             "dashboard-health-snapshot-event-copy-dashboard-lifecycle-event-health"

    assert copy["button_class"] == "btn btn-ghost btn-xs shrink-0"
    assert copy["icon"] == "hero-clipboard-document"
    assert copy["icon_class"] == "h-3.5 w-3.5"
    assert copy["label"] == "Copy"

    assert copy["data_attrs"] == %{
             "data-dashboard-health-snapshot-event-copy" => "dashboard-lifecycle-event-health",
             "data-dashboard-health-snapshot-id" => "health-snapshot-1",
             "data-dashboard-health-snapshot-schema" => "dashboard_health_snapshot.v1"
           }

    snapshot_json = copy["clipboard_text"]

    assert Jason.decode!(snapshot_json) == snapshot

    assert copy == %{
             "button_class" => "btn btn-ghost btn-xs shrink-0",
             "button_id" =>
               "dashboard-health-snapshot-event-copy-dashboard-lifecycle-event-health",
             "clipboard_text" => snapshot_json,
             "data_attrs" => %{
               "data-dashboard-health-snapshot-event-copy" => "dashboard-lifecycle-event-health",
               "data-dashboard-health-snapshot-id" => "health-snapshot-1",
               "data-dashboard-health-snapshot-schema" => "dashboard_health_snapshot.v1"
             },
             "icon" => "hero-clipboard-document",
             "icon_class" => "h-3.5 w-3.5",
             "label" => "Copy"
           }

    assert copy_host["class"] == "contents"
    refute vue.ssr
  end

  test "event_details does not render non-health lifecycle events" do
    event = lifecycle_event("dashboard-lifecycle-event-1", :published)

    html = render_component(&HealthSnapshotActivityComponents.event_details/1, event: event)
    document = LazyHTML.from_fragment(html)

    assert [] =
             document
             |> LazyHTML.query("[data-dashboard-health-snapshot-event]")
             |> LazyHTML.attribute("data-dashboard-health-snapshot-id")

    assert [] =
             document
             |> LazyHTML.query(
               "#dashboard-health-snapshot-event-dashboard-lifecycle-event-1-component"
             )
             |> LazyHTML.attribute("id")
  end

  test "event_details renders no island when the health snapshot builder reports absent" do
    event =
      lifecycle_event(
        "dashboard-lifecycle-event-empty-health",
        :health_snapshot_captured,
        payload: %{"snapshot" => %{}}
      )

    html = render_component(&HealthSnapshotActivityComponents.event_details/1, event: event)

    assert [] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query(
               "#dashboard-health-snapshot-event-dashboard-lifecycle-event-empty-health-component"
             )
             |> LazyHTML.attribute("id")
  end

  test "event_details preserves raw attribute and body rendering semantics" do
    event =
      lifecycle_event(
        "attribute-semantics",
        :health_snapshot_captured,
        payload: %{
          "schema" => nil,
          "source" => false,
          "snapshot_id" => nil,
          "snapshot_schema" => "",
          "health_state" => true,
          "health_severity" => 7,
          "captured_reason" => "",
          "snapshot" => %{
            "counts" => %{
              "widgets" => nil,
              "ready" => false,
              "affected" => true,
              "blocked" => "",
              "stale" => 7
            },
            "placement_ids" => %{"affected" => [nil, false, true, "", 7]}
          }
        }
      )

    for {event_id, expected_attr} <- [
          {nil, :omitted},
          {false, :omitted},
          {true, ""},
          {"", ""},
          {7, "7"}
        ] do
      event = %{event | dashboard_lifecycle_event_id: event_id}
      event_id_text = if is_nil(event_id), do: "", else: to_string(event_id)
      html = render_component(&HealthSnapshotActivityComponents.event_details/1, event: event)

      vue =
        LiveVue.Test.get_vue(html,
          id: "dashboard-health-snapshot-event-#{event_id_text}-component"
        )

      root_attrs = vue.props["presentation"]["root"]["attrs"]
      copy_attrs = vue.props["presentation"]["copy_props"]["data_attrs"]

      if expected_attr == :omitted do
        refute Map.has_key?(root_attrs, "data-dashboard-health-snapshot-event")
        refute Map.has_key?(copy_attrs, "data-dashboard-health-snapshot-event-copy")
      else
        assert root_attrs["data-dashboard-health-snapshot-event"] == expected_attr
        assert copy_attrs["data-dashboard-health-snapshot-event-copy"] == expected_attr
      end

      assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    end

    html = render_component(&HealthSnapshotActivityComponents.event_details/1, event: event)

    vue =
      LiveVue.Test.get_vue(html,
        id: "dashboard-health-snapshot-event-attribute-semantics-component"
      )

    presentation = vue.props["presentation"]

    assert presentation["root"]["attrs"] == %{
             "data-dashboard-health-snapshot-capture-schema" => "",
             "data-dashboard-health-snapshot-event" => "attribute-semantics",
             "data-dashboard-health-snapshot-id" => "",
             "data-dashboard-health-snapshot-reason" => "",
             "data-dashboard-health-snapshot-schema" => "",
             "data-dashboard-health-snapshot-severity" => "7",
             "data-dashboard-health-snapshot-source" => "",
             "data-dashboard-health-snapshot-state" => "true"
           }

    assert Enum.map(presentation["summary"]["rows"], & &1["value"]["text"]) ==
             ["", "true", "7"]

    assert Enum.map(presentation["counts"]["rows"], & &1["value"]["text"]) ==
             ["0", "0", "true", "", "7", "0"]

    assert presentation["placements"]["visible"]
    [placement] = presentation["placements"]["rows"]

    assert placement["value"]["attrs"]["data-dashboard-health-snapshot-placement-ids"] ==
             ",false,true,,7"

    assert placement["value"]["text"] == ", false, true, , 7"

    no_placements_snapshot = Map.put(event.payload["snapshot"], "placement_ids", %{})

    no_placements_event = %{
      event
      | dashboard_lifecycle_event_id: "no-placements",
        payload: Map.put(event.payload, "snapshot", no_placements_snapshot)
    }

    no_placements_html =
      render_component(&HealthSnapshotActivityComponents.event_details/1,
        event: no_placements_event
      )

    no_placements =
      no_placements_html
      |> LiveVue.Test.get_vue(id: "dashboard-health-snapshot-event-no-placements-component")
      |> Map.fetch!(:props)
      |> Map.fetch!("presentation")
      |> Map.fetch!("placements")

    refute no_placements["visible"]
    assert no_placements["rows"] == []
  end
end
