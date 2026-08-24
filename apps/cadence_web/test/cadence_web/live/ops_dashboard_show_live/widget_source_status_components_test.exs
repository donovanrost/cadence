defmodule CadenceWeb.OpsDashboardShowLive.WidgetSourceStatusComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetSourceStatusComponents

  test "source-status presentation preserves actionable evidence and inventory controls" do
    presentation = source_badge_presentation(source_status())
    attrs = presentation["badge"]["attrs"]

    assert presentation["wrapper"] == %{"tag" => "span", "class" => "join"}
    assert presentation["badge"]["tag"] == "button"
    assert presentation["badge"]["text"] == "Source stale"
    assert attrs["phx-click"] == "open_evidence"
    assert attrs["data-widget-source-badge-label"] == "Source stale"
    assert attrs["data-widget-source-badge-inventory-action"] == "source_inventory"

    inventory_query = attrs["data-widget-source-badge-inventory-query"]

    assert inventory_query =~ "contact_id=contact-1"
    assert inventory_query =~ "data_source_id=questdb-flight"
    assert inventory_query =~ "source_binding_id=binding-flight"
    assert inventory_query =~ "source_endpoint_id=endpoint-1"

    inventory_link = presentation["inventory_link"]
    assert inventory_link["tag"] == "a"
    assert inventory_link["attrs"]["data-widget-source-badge-inventory-open"] == "stale"
    href = inventory_link["attrs"]["href"]

    assert href =~ "/missions/mission-1/ops/data-sources?"
    assert href =~ "data_source_id=questdb-flight"
  end

  test "source-status presentation preserves passive tag without evidence context" do
    presentation =
      source_badge_presentation(%{state: :no_data, severity: :info, data_state: :no_data})

    assert presentation["wrapper"] == nil
    assert presentation["inventory_link"] == nil
    assert presentation["badge"]["tag"] == "span"
    assert presentation["badge"]["text"] == "No source"
    assert presentation["badge"]["attrs"]["data-widget-source-badge-action"] == "none"
    refute Map.has_key?(presentation["badge"]["attrs"], "phx-click")
  end

  test "source-status presentation preserves full no-data source context" do
    presentation = source_badge_presentation(no_data_source_status())
    attrs = presentation["badge"]["attrs"]

    assert attrs["phx-click"] == "open_evidence"
    assert attrs["data-widget-source-badge-label"] == "No source"
    assert attrs["data-widget-source-badge-severity"] == "info"
    assert attrs["data-widget-source-badge-source"] == "operational_observables"
    assert attrs["data-widget-source-badge-data-source"] == "managed_operational_observables"

    assert attrs["data-widget-source-badge-binding"] ==
             "default_flight_operational_observables"

    assert attrs["data-widget-source-badge-time-mode"] == "archive"
    assert attrs["data-widget-source-badge-scope-kind"] == "link"
    assert attrs["data-widget-source-badge-scope-id"] == "link-alpha"
    assert attrs["data-widget-source-badge-empty-reason"] == "scope_no_data"

    inventory_query = attrs["data-widget-source-badge-inventory-query"]

    assert inventory_query =~ "data_source_id=managed_operational_observables"
    assert inventory_query =~ "logical_source=operational_observables"
    assert inventory_query =~ "scope_id=link-alpha"
    assert inventory_query =~ "source_empty_reason=scope_no_data"

    href = presentation["inventory_link"]["attrs"]["href"]

    assert href =~ "/missions/mission-1/ops/data-sources?"
    assert href =~ "data_source_id=managed_operational_observables"
  end

  test "source-status presentation preserves partial evidence as actionable warning" do
    presentation =
      source_badge_presentation(%{
        state: :partial,
        severity: :warning,
        data_state: :ready,
        logical_sources: [:telemetry],
        data_source_ids: ["questdb-flight"],
        source_binding_ids: ["binding-flight"]
      })

    assert presentation["badge"]["class"] ==
             "badge badge-xs gap-1 cursor-pointer join-item badge-warning badge-outline"

    assert presentation["badge"]["attrs"]["phx-click"] == "open_evidence"

    assert presentation["badge"]["attrs"]["data-widget-source-badge-label"] ==
             "Source partial"
  end

  test "widget_query_diagnostics exposes query context and evidence attrs" do
    vue = render_widget_query()

    assert vue.component == "WidgetQueryDiagnostics"
    assert vue.id == "widget-query-placement-1-component"
    refute vue.ssr
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    presentation = vue.props["presentation"]
    assert presentation["component_id"] == "widget-query-placement-1-component"

    assert presentation["overlay"] == %{
             "id" => "widget-query-placement-1",
             "class" => "cadence-overlay",
             "attrs" => %{
               "data-overlay-kind" => "popover",
               "data-overlay-placement" => "bottom-end",
               "data-widget-query-diagnostics" => "",
               "data-widget-query-data-view" => "all_revisions",
               "data-widget-query-compare-data-view" => "canonical",
               "data-widget-query-binding-source" => "telemetry",
               "data-widget-query-binding-mode" => "fixed",
               "data-widget-query-observables" => "HK.voltage",
               "data-widget-query-sampling" => "latest",
               "data-widget-query-window-seconds" => "300",
               "data-widget-query-source-state" => "stale",
               "data-widget-query-source-data-state" => "ready",
               "data-widget-query-source-request-ids" => "source-req-1",
               "data-widget-query-logical-sources" => "telemetry",
               "data-widget-query-data-source-ids" => "questdb-flight",
               "data-widget-query-source-binding-ids" => "binding-flight",
               "data-widget-query-realms" => "flight",
               "data-widget-query-time-modes" => "archive",
               "data-widget-query-time-axes" => "receipt_time",
               "data-widget-query-scope-kinds" => "spacecraft",
               "data-widget-query-scope-ids" => "spacecraft-1",
               "data-widget-query-contact-ids" => "contact-1",
               "data-widget-query-source-endpoint-ids" => "endpoint-1",
               "data-widget-query-source-health-states" => "degraded",
               "data-widget-query-source-health-reasons" => "source_schema_probe_failed",
               "data-widget-query-source-health-event-ids" => "source-health-event-1",
               "data-widget-query-empty-reason" => "contact_scope_no_data",
               "data-widget-query-warning-codes" => "stale_data"
             }
           }

    assert presentation["trigger"] == %{
             "id" => "widget-query-placement-1-trigger",
             "type" => "button",
             "class" => "cadence-overlay-trigger",
             "attrs" => %{
               "data-overlay-trigger" => "",
               "aria-haspopup" => "dialog",
               "aria-expanded" => "false",
               "aria-controls" => "widget-query-placement-1-panel",
               "aria-label" => "Widget query diagnostics"
             },
             "content" => %{
               "class" => "btn btn-ghost btn-xs btn-square",
               "attrs" => %{
                 "title" =>
                   "Widget query | Data view: all_revisions | Compare view: canonical | Requested source: telemetry",
                 "data-widget-query-diagnostics-open" => ""
               },
               "icon" => %{
                 "name" => "hero-adjustments-horizontal",
                 "class" => "h-3.5 w-3.5"
               }
             }
           }

    assert presentation["panel"] == %{
             "id" => "widget-query-placement-1-panel",
             "class" => "cadence-overlay-panel cadence-popover-panel",
             "hidden" => true,
             "attrs" => %{
               "data-overlay-panel" => "",
               "data-overlay-width" => "md",
               "aria-label" => "Widget query diagnostics"
             }
           }

    body = presentation["body"]

    assert Map.drop(body, ["rows", "evidence_button"]) == %{
             "class" => "p-2 text-xs",
             "heading" => %{
               "class" => "font-semibold text-base-content",
               "text" => "Widget query"
             },
             "rows_class" => "mt-2 grid grid-cols-[7.25rem_minmax(0,1fr)] gap-x-2 gap-y-1"
           }

    assert Enum.map(body["rows"], fn row ->
             {
               row["order"],
               row["key"],
               row["label"]["class"],
               row["label"]["attrs"]["data-widget-query-field"],
               row["label"]["text"],
               row["value"]["class"],
               row["value"]["attrs"]["data-widget-query-value"],
               row["value"]["text"]
             }
           end) == [
             {0, "widget-query-placement-1-row-0", "text-base-content/60", "Data view",
              "Data view", "font-mono text-base-content break-all", "data_view", "all_revisions"},
             {1, "widget-query-placement-1-row-1", "text-base-content/60", "Compare view",
              "Compare view", "font-mono text-base-content break-all", "compare_data_view",
              "canonical"},
             {2, "widget-query-placement-1-row-2", "text-base-content/60", "Requested source",
              "Requested source", "font-mono text-base-content break-all", "binding_source",
              "telemetry"},
             {3, "widget-query-placement-1-row-3", "text-base-content/60", "Binding mode",
              "Binding mode", "font-mono text-base-content break-all", "binding_mode", "fixed"},
             {4, "widget-query-placement-1-row-4", "text-base-content/60", "Observables",
              "Observables", "font-mono text-base-content break-all", "observables",
              "HK.voltage"},
             {5, "widget-query-placement-1-row-5", "text-base-content/60", "Sampling", "Sampling",
              "font-mono text-base-content break-all", "sampling", "latest"},
             {6, "widget-query-placement-1-row-6", "text-base-content/60", "Window seconds",
              "Window seconds", "font-mono text-base-content break-all", "window_seconds", "300"},
             {7, "widget-query-placement-1-row-7", "text-base-content/60", "Source state",
              "Source state", "font-mono text-base-content break-all", "source_state", "stale"},
             {8, "widget-query-placement-1-row-8", "text-base-content/60", "Data state",
              "Data state", "font-mono text-base-content break-all", "data_state", "ready"},
             {9, "widget-query-placement-1-row-9", "text-base-content/60", "Source requests",
              "Source requests", "font-mono text-base-content break-all", "source_requests",
              "source-req-1"},
             {10, "widget-query-placement-1-row-10", "text-base-content/60", "Logical sources",
              "Logical sources", "font-mono text-base-content break-all", "logical_sources",
              "telemetry"},
             {11, "widget-query-placement-1-row-11", "text-base-content/60", "Data sources",
              "Data sources", "font-mono text-base-content break-all", "data_sources",
              "questdb-flight"},
             {12, "widget-query-placement-1-row-12", "text-base-content/60", "Source bindings",
              "Source bindings", "font-mono text-base-content break-all", "source_bindings",
              "binding-flight"},
             {13, "widget-query-placement-1-row-13", "text-base-content/60", "Realms", "Realms",
              "font-mono text-base-content break-all", "realms", "flight"},
             {14, "widget-query-placement-1-row-14", "text-base-content/60", "Time", "Time",
              "font-mono text-base-content break-all", "time", "archive/receipt_time"},
             {15, "widget-query-placement-1-row-15", "text-base-content/60", "Scope", "Scope",
              "font-mono text-base-content break-all", "scope", "spacecraft/spacecraft-1"},
             {16, "widget-query-placement-1-row-16", "text-base-content/60", "Contacts",
              "Contacts", "font-mono text-base-content break-all", "contacts", "contact-1"},
             {17, "widget-query-placement-1-row-17", "text-base-content/60", "Source endpoints",
              "Source endpoints", "font-mono text-base-content break-all", "source_endpoints",
              "endpoint-1"},
             {18, "widget-query-placement-1-row-18", "text-base-content/60", "Source health",
              "Source health", "font-mono text-base-content break-all", "source_health",
              "degraded"},
             {19, "widget-query-placement-1-row-19", "text-base-content/60", "Health reasons",
              "Health reasons", "font-mono text-base-content break-all", "source_health_reasons",
              "source_schema_probe_failed"},
             {20, "widget-query-placement-1-row-20", "text-base-content/60", "Health events",
              "Health events", "font-mono text-base-content break-all", "source_health_events",
              "source-health-event-1"},
             {21, "widget-query-placement-1-row-21", "text-base-content/60", "Empty reason",
              "Empty reason", "font-mono text-base-content break-all", "empty_reason",
              "contact_scope_no_data"},
             {22, "widget-query-placement-1-row-22", "text-base-content/60", "Warnings",
              "Warnings", "font-mono text-base-content break-all", "warning_codes", "stale_data"}
           ]

    assert body["evidence_button"] == %{
             "type" => "button",
             "class" => "btn btn-xs btn-outline mt-2 w-full justify-start",
             "attrs" => %{
               "data-widget-query-evidence-open" => "",
               "phx-click" => "open_evidence",
               "phx-value-kind" => "query",
               "phx-value-placement-id" => "placement-1",
               "phx-value-widget-title" => "Voltage",
               "phx-value-requested-data-view" => "all_revisions",
               "phx-value-compare-data-view" => "canonical",
               "phx-value-binding-source" => "telemetry",
               "phx-value-binding-mode" => "fixed",
               "phx-value-observables" => "HK.voltage",
               "phx-value-sampling" => "latest",
               "phx-value-window-seconds" => "300",
               "phx-value-source-evidence-state" => "stale",
               "phx-value-data-state" => "ready",
               "phx-value-source-request-id" => "source-req-1",
               "phx-value-logical-source" => "telemetry",
               "phx-value-realm" => "flight",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-source-binding-id" => "binding-flight",
               "phx-value-time-mode" => "archive",
               "phx-value-time-axis" => "receipt_time",
               "phx-value-replay-run-id" => "nil",
               "phx-value-scope-kind" => "spacecraft",
               "phx-value-scope-id" => "spacecraft-1",
               "phx-value-scope-ids" => "spacecraft-1",
               "phx-value-contact-id" => "contact-1",
               "phx-value-contact-ids" => "contact-1",
               "phx-value-source-endpoint-id" => "endpoint-1",
               "phx-value-source-health-state" => "degraded",
               "phx-value-source-health-reason" => "source_schema_probe_failed",
               "phx-value-source-health-event-id" => "source-health-event-1",
               "phx-value-source-empty-reason" => "contact_scope_no_data",
               "phx-value-widget-warning-codes" => "stale_data"
             },
             "icon" => %{"name" => "hero-link", "class" => "h-3.5 w-3.5"},
             "text" => "Open query evidence"
           }
  end

  test "widget query DTO preserves HEEx attribute and body value semantics" do
    cases = [
      %{value: nil, normalized: "", event: :absent, body: :absent},
      %{value: false, normalized: "false", event: :absent, body: "false"},
      %{value: true, normalized: "true", event: "", body: "true"},
      %{value: "", normalized: "", event: :absent, body: :absent},
      %{value: 42, normalized: "42", event: "42", body: "42"}
    ]

    Enum.each(cases, fn test_case ->
      vue =
        render_widget_query(
          widget: Map.put(widget(), :title, test_case.value),
          data: %{},
          data_view: test_case.value,
          compare_data_view: nil,
          warnings: []
        )

      presentation = vue.props["presentation"]
      overlay_attrs = presentation["overlay"]["attrs"]
      evidence_attrs = presentation["body"]["evidence_button"]["attrs"]

      assert presentation == Jason.decode!(Jason.encode!(presentation))
      assert overlay_attrs["data-widget-query-diagnostics"] == ""
      assert overlay_attrs["data-widget-query-data-view"] == test_case.normalized

      if test_case.event == :absent do
        refute Map.has_key?(evidence_attrs, "phx-value-widget-title")
      else
        assert evidence_attrs["phx-value-widget-title"] == test_case.event
      end

      data_view_row =
        Enum.find(
          presentation["body"]["rows"],
          &(&1["value"]["attrs"]["data-widget-query-value"] == "data_view")
        )

      if test_case.body == :absent do
        refute data_view_row
      else
        assert data_view_row["value"]["text"] == test_case.body
      end
    end)
  end

  test "source status and diagnostics predicates classify displayable states" do
    assert WidgetSourceStatusComponents.source_status_badge?(%{
             source_status: %{state: :retention_gap}
           })

    assert WidgetSourceStatusComponents.source_status_badge?(%{
             source_status: %{state: :degraded}
           })

    refute WidgetSourceStatusComponents.source_status_badge?(%{source_status: %{state: :fresh}})

    assert WidgetSourceStatusComponents.widget_query_diagnostics?(
             widget(),
             %{source_status: source_status()},
             "canonical",
             nil
           )
  end

  defp render_widget_query(attrs \\ []) do
    attrs =
      Keyword.merge(
        [
          widget: widget(),
          placement_id: "placement-1",
          data: %{source_status: source_status()},
          data_view: "all_revisions",
          compare_data_view: "canonical",
          warnings: [%{code_text: "stale_data"}]
        ],
        attrs
      )

    html = render_component(&WidgetSourceStatusComponents.widget_query_diagnostics/1, attrs)
    LiveVue.Test.get_vue(html, id: "widget-query-placement-1-component")
  end

  defp source_badge_presentation(source_status) do
    source_status
    |> WidgetSourceStatusComponents.source_status_badge_presentation("mission-1")
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp widget do
    %{
      title: "Voltage",
      binding: %{
        source: :telemetry,
        mode: :fixed,
        point_id: "HK.voltage",
        sampling: :latest
      },
      options: %{window_seconds: 300}
    }
  end

  defp source_status do
    %{
      state: :stale,
      severity: :warning,
      data_state: :ready,
      stale?: true,
      warning_codes: [:stale_data],
      source_request_ids: ["source-req-1"],
      logical_sources: [:telemetry],
      data_source_ids: ["questdb-flight"],
      source_binding_ids: ["binding-flight"],
      realms: [:flight],
      time_modes: [:archive],
      time_axes: [:receipt_time],
      scope_kinds: [:spacecraft],
      scope_ids: ["spacecraft-1"],
      contact_ids: ["contact-1"],
      source_endpoint_ids: ["endpoint-1"],
      source_health_states: [:degraded],
      source_health_reasons: [:source_schema_probe_failed],
      source_health_event_ids: ["source-health-event-1"],
      empty_reason: :contact_scope_no_data
    }
  end

  defp no_data_source_status do
    %{
      state: :no_data,
      severity: :info,
      data_state: :no_data,
      stale?: false,
      warning_codes: [],
      source_request_ids: ["source-request-empty"],
      logical_sources: [:operational_observables],
      data_source_ids: ["managed_operational_observables"],
      source_binding_ids: ["default_flight_operational_observables"],
      realms: [:flight],
      time_modes: [:archive],
      time_axes: [:generation_time],
      scope_kinds: [:link],
      scope_ids: ["link-alpha"],
      source_endpoint_ids: ["source-endpoint-alpha"],
      empty_reason: :scope_no_data
    }
  end
end
