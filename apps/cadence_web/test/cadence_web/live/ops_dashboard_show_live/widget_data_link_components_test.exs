defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataLinkComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetDataLinkComponents

  test "widget_data_link_menu carries source and time context params" do
    vue =
      render_vue(
        &WidgetDataLinkComponents.widget_data_link_menu/1,
        [links: [presented_link()], placement_id: "placement-1"],
        "widget-data-links-placement-1-component"
      )

    assert_vue_host(vue, "widget-data-links-placement-1-component")
    presentation = vue.props["presentation"]
    assert presentation["kind"] == "widget"
    assert presentation["component_id"] == "widget-data-links-placement-1-component"

    assert presentation["overlay"] == %{
             "attrs" => %{
               "data-overlay-kind" => "popover",
               "data-overlay-placement" => "bottom-end",
               "data-widget-data-links" => ""
             },
             "class" => "cadence-overlay",
             "id" => "widget-data-links-placement-1"
           }

    assert presentation["trigger"] == %{
             "attrs" => %{
               "aria-controls" => "widget-data-links-placement-1-panel",
               "aria-expanded" => "false",
               "aria-haspopup" => "dialog",
               "aria-label" => "Inspect widget data",
               "data-overlay-trigger" => ""
             },
             "class" => "cadence-overlay-trigger",
             "content" => %{
               "attrs" => %{"data-widget-data-link-menu" => ""},
               "class" => "btn btn-ghost btn-xs btn-square",
               "icon" => %{
                 "class" => "h-3.5 w-3.5",
                 "name" => "hero-magnifying-glass"
               },
               "title" => "Inspect widget data"
             },
             "id" => "widget-data-links-placement-1-trigger",
             "type" => "button"
           }

    assert presentation["panel"] == %{
             "attrs" => %{
               "aria-label" => "Inspect widget data",
               "data-overlay-panel" => "",
               "data-overlay-width" => "sm"
             },
             "class" => "cadence-overlay-panel cadence-popover-panel",
             "hidden" => true,
             "id" => "widget-data-links-placement-1-panel"
           }

    assert presentation["body"] == %{"class" => "p-1 text-xs"}
    [link] = presentation["items"]

    assert link["attrs"]["phx-value-link-id"] == "link-1"
    assert link["attrs"]["phx-value-realm"] == "flight"
    assert link["attrs"]["phx-value-data-view"] == "canonical"
    assert link["attrs"]["phx-value-data-source-id"] == "questdb-flight"
    assert link["attrs"]["phx-value-source-binding-id"] == "binding-flight"
    assert link["attrs"]["phx-value-time-mode"] == "archive"
    assert link["attrs"]["phx-value-time-axis"] == "receipt_time"

    assert link == %{
             "attrs" => %{
               "data-widget-data-link-id" => "sample-1",
               "data-widget-data-link-ref" => "link-1",
               "data-widget-data-link-target" => "telemetry_sample",
               "phx-click" => "open_data_link",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-data-view" => "canonical",
               "phx-value-link-id" => "link-1",
               "phx-value-placement-id" => "placement-1",
               "phx-value-realm" => "flight",
               "phx-value-replay-run-id" => "replay-run-1",
               "phx-value-source-binding-id" => "binding-flight",
               "phx-value-target" => "telemetry_sample",
               "phx-value-target-id" => "sample-1",
               "phx-value-time-axis" => "receipt_time",
               "phx-value-time-mode" => "archive"
             },
             "class" =>
               "flex w-full items-center justify-between gap-2 rounded px-2 py-1 text-left hover:bg-base-200",
             "icon" => nil,
             "key" => "widget-data-links-placement-1-item-0",
             "kind" => "data_link",
             "label" => %{"class" => nil, "text" => "Sample"},
             "secondary" => %{
               "class" => "font-mono text-base-content/60 truncate",
               "text" => "sample-1"
             },
             "type" => "button"
           }
  end

  test "status_matrix_row_link_menu exposes row frame evidence and row links" do
    vue =
      render_vue(
        &WidgetDataLinkComponents.status_matrix_row_link_menu/1,
        [
          row: status_row(),
          links: [presented_link()],
          placement_id: "placement-1"
        ],
        "status-row-links-placement-1-battery.voltage-component"
      )

    assert_vue_host(vue, "status-row-links-placement-1-battery.voltage-component")
    presentation = vue.props["presentation"]
    assert presentation["kind"] == "status_matrix_row"
    assert presentation["overlay"]["id"] == "status-row-links-placement-1-battery.voltage"
    assert presentation["overlay"]["attrs"]["data-status-matrix-row-links"] == "battery.voltage"

    assert presentation["trigger"]["content"]["attrs"] == %{
             "data-status-matrix-row-link-menu" => "battery.voltage"
           }

    [evidence, link] = presentation["items"]

    assert evidence["attrs"]["data-status-matrix-row-evidence-observable"] ==
             "ccsds.frame.apid.100"

    assert evidence["attrs"]["phx-click"] == "open_evidence"
    assert evidence["attrs"]["phx-value-scope-kind"] == "transport"
    assert evidence["attrs"]["phx-value-scope-id"] == "transport-alpha"
    assert evidence["attrs"]["phx-value-scope-ids"] == "transport-alpha,transport-beta"
    assert link["attrs"]["phx-value-link-id"] == "link-1"
    assert link["attrs"]["data-status-matrix-row-link-id"] == "sample-1"

    assert evidence["kind"] == "evidence"
    assert evidence["type"] == "button"
    assert evidence["label"] == %{"class" => nil, "text" => "Frame evidence"}

    assert evidence["icon"] == %{
             "class" => "h-3.5 w-3.5",
             "name" => "hero-document-magnifying-glass"
           }

    assert link["kind"] == "data_link"
    assert link["attrs"]["phx-click"] == "open_data_link"
    assert Enum.map(presentation["items"], & &1["kind"]) == ["evidence", "data_link"]
  end

  test "data_table_row_link_menu exposes query-scoped row frame evidence" do
    vue =
      render_vue(
        &WidgetDataLinkComponents.data_table_row_link_menu/1,
        [
          row: data_table_row(),
          links: [presented_link()],
          placement_id: "placement-1"
        ],
        "data-row-links-placement-1-commanding.queue_depth:endpoint-alpha-component"
      )

    assert_vue_host(
      vue,
      "data-row-links-placement-1-commanding.queue_depth:endpoint-alpha-component"
    )

    presentation = vue.props["presentation"]
    assert presentation["kind"] == "data_table_row"
    [evidence, link] = presentation["items"]

    assert evidence["attrs"]["data-data-table-row-evidence-observable"] ==
             "commanding.queue_depth"

    assert evidence["attrs"]["phx-value-scope-kind"] == "source_endpoint"
    assert evidence["attrs"]["phx-value-scope-id"] == "endpoint-alpha"
    assert evidence["attrs"]["phx-value-scope-ids"] == "endpoint-alpha,endpoint-beta"

    assert evidence["attrs"] == %{
             "data-data-table-row-evidence" => "commanding.queue_depth:endpoint-alpha",
             "data-data-table-row-evidence-observable" => "commanding.queue_depth",
             "phx-click" => "open_evidence",
             "phx-value-kind" => "frame",
             "phx-value-observable-id" => "commanding.queue_depth",
             "phx-value-placement-id" => "placement-1",
             "phx-value-scope-id" => "endpoint-alpha",
             "phx-value-scope-ids" => "endpoint-alpha,endpoint-beta",
             "phx-value-scope-kind" => "source_endpoint"
           }

    assert link["attrs"]["data-data-table-row-link"] ==
             "commanding.queue_depth:endpoint-alpha"

    assert link["attrs"]["phx-click"] == "open_data_link"
  end

  test "state and event timeline menus own exact server-side millisecond conversion" do
    state_vue =
      render_vue(
        &WidgetDataLinkComponents.state_timeline_row_link_menu/1,
        [
          row: %{
            row_id: "state-1",
            observable_id: "tlm.mode",
            starts_at: ~U[2026-06-17 12:00:01.234Z]
          },
          links: [presented_link()],
          placement_id: "placement-1"
        ],
        "state-row-links-placement-1-state-1-component"
      )

    event_vue =
      render_vue(
        &WidgetDataLinkComponents.event_timeline_row_link_menu/1,
        [
          row: %{
            row_id: "event-1",
            title: "Burn started",
            occurred_at: ~U[2026-06-17 12:00:02.345Z]
          },
          links: [presented_link()],
          placement_id: "placement-1"
        ],
        "event-row-links-placement-1-event-1-component"
      )

    assert_vue_host(state_vue, "state-row-links-placement-1-state-1-component")
    assert_vue_host(event_vue, "event-row-links-placement-1-event-1-component")

    state_presentation = state_vue.props["presentation"]
    event_presentation = event_vue.props["presentation"]
    assert state_presentation["kind"] == "state_timeline_row"
    assert event_presentation["kind"] == "event_timeline_row"

    assert Enum.map(state_presentation["items"], & &1["kind"]) == [
             "evidence",
             "data_link"
           ]

    assert Enum.map(event_presentation["items"], & &1["kind"]) == ["data_link"]

    [state_evidence, state_link] = state_presentation["items"]
    [event_link] = event_presentation["items"]

    assert state_evidence["attrs"]["phx-click"] == "open_evidence"
    assert state_link["attrs"]["phx-value-timestamp-ms"] == "1781697601234"
    assert event_link["attrs"]["phx-value-timestamp-ms"] == "1781697602345"
    assert event_link["attrs"]["phx-click"] == "open_data_link"
    assert event_presentation["trigger"]["attrs"]["aria-label"] == "Inspect Burn started"
    assert event_presentation["trigger"]["content"]["title"] == "Inspect Burn started"
  end

  test "all five menu kinds preserve empty-link and evidence-only variants" do
    presentations = [
      render_presentation(
        &WidgetDataLinkComponents.widget_data_link_menu/1,
        [links: [], placement_id: "placement-1"],
        "widget-data-links-placement-1-component"
      ),
      render_presentation(
        &WidgetDataLinkComponents.status_matrix_row_link_menu/1,
        [row: status_row(), links: [], placement_id: "placement-1"],
        "status-row-links-placement-1-battery.voltage-component"
      ),
      render_presentation(
        &WidgetDataLinkComponents.data_table_row_link_menu/1,
        [row: data_table_row(), links: [], placement_id: "placement-1"],
        "data-row-links-placement-1-commanding.queue_depth:endpoint-alpha-component"
      ),
      render_presentation(
        &WidgetDataLinkComponents.state_timeline_row_link_menu/1,
        [
          row: %{row_id: "state-1", observable_id: "tlm.mode"},
          links: [],
          placement_id: "placement-1"
        ],
        "state-row-links-placement-1-state-1-component"
      ),
      render_presentation(
        &WidgetDataLinkComponents.event_timeline_row_link_menu/1,
        [row: %{row_id: "event-1", title: "Event"}, links: [], placement_id: "placement-1"],
        "event-row-links-placement-1-event-1-component"
      )
    ]

    assert Enum.map(presentations, & &1["kind"]) == [
             "widget",
             "status_matrix_row",
             "data_table_row",
             "state_timeline_row",
             "event_timeline_row"
           ]

    assert Enum.map(presentations, &Enum.map(&1["items"], fn item -> item["kind"] end)) == [
             [],
             ["evidence"],
             ["evidence"],
             ["evidence"],
             []
           ]

    assert Enum.all?(presentations, fn presentation ->
             presentation["panel"]["hidden"] == true and
               presentation["trigger"]["attrs"]["aria-expanded"] == "false"
           end)
  end

  test "DTOs round-trip through JSON while preserving empty and absent attributes" do
    link = %{presented_link() | label: nil, link_id: nil, target_id: nil, target_text: nil}

    presentation =
      render_presentation(
        &WidgetDataLinkComponents.widget_data_link_menu/1,
        [links: [link], placement_id: "placement-1"],
        "widget-data-links-placement-1-component"
      )

    assert presentation == Jason.decode!(Jason.encode!(presentation))
    [item] = presentation["items"]
    assert item["attrs"]["data-widget-data-link-id"] == ""
    assert item["attrs"]["data-widget-data-link-ref"] == ""
    refute Map.has_key?(item["attrs"], "data-widget-data-link-target")
    refute Map.has_key?(item["attrs"], "phx-value-link-id")
    refute Map.has_key?(item["attrs"], "phx-value-target-id")
    refute Map.has_key?(item["attrs"], "phx-value-timestamp-ms")
    assert item["label"]["text"] == ""
    assert item["secondary"]["text"] == ""
    refute Map.has_key?(item, "href")

    nil_row_presentation =
      render_presentation(
        &WidgetDataLinkComponents.status_matrix_row_link_menu/1,
        [row: %{observable_id: nil}, links: [], placement_id: "placement-1"],
        "status-row-links-placement-1--component"
      )

    assert nil_row_presentation == Jason.decode!(Jason.encode!(nil_row_presentation))
    [evidence] = nil_row_presentation["items"]

    refute Map.has_key?(
             nil_row_presentation["overlay"]["attrs"],
             "data-status-matrix-row-links"
           )

    refute Map.has_key?(
             nil_row_presentation["trigger"]["content"]["attrs"],
             "data-status-matrix-row-link-menu"
           )

    refute Map.has_key?(evidence["attrs"], "data-status-matrix-row-evidence")
    refute Map.has_key?(evidence["attrs"], "data-status-matrix-row-evidence-observable")
    refute Map.has_key?(evidence["attrs"], "phx-value-observable-id")
  end

  test "text and direct attributes preserve nil false true HEEx semantics" do
    nil_link = %{
      presented_link()
      | label: nil,
        link_id: nil,
        target: nil,
        target_id: nil,
        target_text: nil
    }

    nil_row_cases = [
      %{
        component: &WidgetDataLinkComponents.status_matrix_row_link_menu/1,
        row: %{observable_id: nil},
        component_id: "status-row-links-placement-1--component",
        overlay_id: "status-row-links-placement-1-",
        label: "Inspect ",
        overlay_attr: "data-status-matrix-row-links",
        trigger_attr: "data-status-matrix-row-link-menu",
        link_attr: "data-status-matrix-row-link",
        evidence_attrs: [
          "data-status-matrix-row-evidence",
          "data-status-matrix-row-evidence-observable"
        ]
      },
      %{
        component: &WidgetDataLinkComponents.data_table_row_link_menu/1,
        row: %{observable_id: nil},
        component_id: "data-row-links-placement-1--component",
        overlay_id: "data-row-links-placement-1-",
        label: "Inspect ",
        overlay_attr: "data-data-table-row-links",
        trigger_attr: "data-data-table-row-link-menu",
        link_attr: "data-data-table-row-link",
        evidence_attrs: [
          "data-data-table-row-evidence",
          "data-data-table-row-evidence-observable"
        ]
      },
      %{
        component: &WidgetDataLinkComponents.state_timeline_row_link_menu/1,
        row: %{row_id: nil, observable_id: nil},
        component_id: "state-row-links-placement-1--component",
        overlay_id: "state-row-links-placement-1-",
        label: "Inspect  state transition",
        overlay_attr: "data-state-timeline-row-links",
        trigger_attr: "data-state-timeline-row-link-menu",
        link_attr: "data-state-timeline-row-link",
        evidence_attrs: [
          "data-state-timeline-row-evidence",
          "data-state-timeline-row-evidence-observable"
        ]
      },
      %{
        component: &WidgetDataLinkComponents.event_timeline_row_link_menu/1,
        row: %{row_id: nil, title: nil},
        component_id: "event-row-links-placement-1--component",
        overlay_id: "event-row-links-placement-1-",
        label: "Inspect ",
        overlay_attr: "data-event-timeline-row-links",
        trigger_attr: "data-event-timeline-row-link-menu",
        link_attr: "data-event-timeline-row-link",
        evidence_attrs: []
      }
    ]

    Enum.each(nil_row_cases, fn test_case ->
      presentation =
        render_presentation(
          test_case.component,
          [row: test_case.row, links: [nil_link], placement_id: "placement-1"],
          test_case.component_id
        )

      assert presentation == Jason.decode!(Jason.encode!(presentation))
      assert presentation["component_id"] == test_case.component_id
      assert presentation["overlay"]["id"] == test_case.overlay_id
      assert presentation["trigger"]["attrs"]["aria-label"] == test_case.label
      assert presentation["trigger"]["content"]["title"] == test_case.label
      refute Map.has_key?(presentation["overlay"]["attrs"], test_case.overlay_attr)

      refute Map.has_key?(
               presentation["trigger"]["content"]["attrs"],
               test_case.trigger_attr
             )

      link = Enum.find(presentation["items"], &(&1["kind"] == "data_link"))
      assert link

      expected_kinds =
        if test_case.evidence_attrs == [], do: ["data_link"], else: ["evidence", "data_link"]

      assert Enum.map(presentation["items"], & &1["kind"]) == expected_kinds
      refute Map.has_key?(link["attrs"], test_case.link_attr)
      refute Map.has_key?(link["attrs"], "#{test_case.link_attr}-target")
      assert link["attrs"]["#{test_case.link_attr}-id"] == ""
      assert link["attrs"]["#{test_case.link_attr}-ref"] == ""

      assert link["label"]["text"] == ""
      assert link["secondary"]["text"] == ""

      if test_case.evidence_attrs != [] do
        evidence = Enum.find(presentation["items"], &(&1["kind"] == "evidence"))
        assert evidence

        Enum.each(test_case.evidence_attrs, fn attr_name ->
          refute Map.has_key?(evidence["attrs"], attr_name)
        end)
      end
    end)

    false_status =
      render_presentation(
        &WidgetDataLinkComponents.status_matrix_row_link_menu/1,
        [row: %{observable_id: false}, links: [], placement_id: "placement-1"],
        "status-row-links-placement-1-false-component"
      )

    assert false_status["overlay"]["id"] == "status-row-links-placement-1-false"
    assert false_status["trigger"]["attrs"]["aria-label"] == "Inspect false"
    refute Map.has_key?(false_status["overlay"]["attrs"], "data-status-matrix-row-links")

    refute Map.has_key?(
             false_status["trigger"]["content"]["attrs"],
             "data-status-matrix-row-link-menu"
           )

    [false_evidence] = false_status["items"]
    refute Map.has_key?(false_evidence["attrs"], "data-status-matrix-row-evidence")

    refute Map.has_key?(
             false_evidence["attrs"],
             "data-status-matrix-row-evidence-observable"
           )

    empty_status =
      render_presentation(
        &WidgetDataLinkComponents.status_matrix_row_link_menu/1,
        [row: %{observable_id: ""}, links: [], placement_id: "placement-1"],
        "status-row-links-placement-1--component"
      )

    assert empty_status["overlay"]["id"] == "status-row-links-placement-1-"
    assert empty_status["trigger"]["attrs"]["aria-label"] == "Inspect "
    assert empty_status["overlay"]["attrs"]["data-status-matrix-row-links"] == ""

    assert empty_status["trigger"]["content"]["attrs"]["data-status-matrix-row-link-menu"] ==
             ""

    [empty_evidence] = empty_status["items"]
    assert empty_evidence["attrs"]["data-status-matrix-row-evidence"] == ""
    assert empty_evidence["attrs"]["data-status-matrix-row-evidence-observable"] == ""

    true_status =
      render_presentation(
        &WidgetDataLinkComponents.status_matrix_row_link_menu/1,
        [row: %{observable_id: true}, links: [], placement_id: "placement-1"],
        "status-row-links-placement-1-true-component"
      )

    assert true_status["overlay"]["id"] == "status-row-links-placement-1-true"
    assert true_status["trigger"]["attrs"]["aria-label"] == "Inspect true"
    assert true_status["overlay"]["attrs"]["data-status-matrix-row-links"] == ""

    assert true_status["trigger"]["content"]["attrs"]["data-status-matrix-row-link-menu"] ==
             ""

    [true_evidence] = true_status["items"]
    assert true_evidence["attrs"]["data-status-matrix-row-evidence"] == ""

    assert true_evidence["attrs"]["data-status-matrix-row-evidence-observable"] == ""

    Enum.each([{false, "false"}, {true, "true"}, {"", ""}], fn {value, expected_text} ->
      link = %{
        presented_link()
        | label: value,
          link_id: value,
          target: value,
          target_id: value,
          target_text: value
      }

      presentation =
        render_presentation(
          &WidgetDataLinkComponents.widget_data_link_menu/1,
          [links: [link], placement_id: "placement-1"],
          "widget-data-links-placement-1-component"
        )

      [item] = presentation["items"]

      if value do
        assert item["attrs"]["data-widget-data-link-target"] == ""
      else
        refute Map.has_key?(item["attrs"], "data-widget-data-link-target")
      end

      assert item["attrs"]["data-widget-data-link-id"] == ""
      assert item["attrs"]["data-widget-data-link-ref"] == ""
      assert item["label"]["text"] == expected_text
      assert item["secondary"]["text"] == expected_text
    end)
  end

  defp render_vue(component, assigns, component_id) do
    component
    |> render_component(assigns)
    |> LiveVue.Test.get_vue(id: component_id)
  end

  defp render_presentation(component, assigns, component_id) do
    component
    |> render_vue(assigns, component_id)
    |> Map.fetch!(:props)
    |> Map.fetch!("presentation")
  end

  defp assert_vue_host(vue, component_id) do
    assert vue.component == "WidgetDataLinks"
    assert vue.id == component_id
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
  end

  defp status_row do
    %{
      observable_id: "battery.voltage",
      frame_observable_id: "ccsds.frame.apid.100",
      query_scope_kind: "transport",
      query_scope_id: "transport-alpha",
      query_scope_ids: ["transport-alpha", "transport-beta"]
    }
  end

  defp data_table_row do
    %{
      observable_id: "commanding.queue_depth:endpoint-alpha",
      frame_observable_id: "commanding.queue_depth",
      query_scope_kind: "source_endpoint",
      query_scope_id: "endpoint-alpha",
      query_scope_ids: ["endpoint-alpha", "endpoint-beta"]
    }
  end

  defp presented_link do
    %{
      link_id: "link-1",
      label: "Sample",
      target: :telemetry_sample,
      target_text: "telemetry_sample",
      target_id: "sample-1",
      context: %{
        data: %{
          realm: :flight,
          view: "canonical",
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight",
          replay_run_id: "replay-run-1"
        },
        time: %{mode: "archive", axis: "receipt_time"}
      }
    }
  end
end
