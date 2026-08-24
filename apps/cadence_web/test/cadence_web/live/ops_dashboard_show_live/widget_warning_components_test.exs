defmodule CadenceWeb.OpsDashboardShowLive.WidgetWarningComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.WidgetWarningComponents

  test "engine_warning_badge renders evidence controls and detail evidence rows" do
    vue = render_vue(warning())
    assert_vue_host(vue, "widget-placement-1-engine-warning-0-component")
    presentation = vue.props["presentation"]

    assert presentation["component_id"] == "widget-placement-1-engine-warning-0-component"

    assert presentation["overlay"] == %{
             "attrs" => %{
               "data-engine-warning-detail" => "source_degraded",
               "data-overlay-kind" => "popover",
               "data-overlay-placement" => "bottom-end"
             },
             "class" => "cadence-overlay",
             "id" => "widget-placement-1-engine-warning-0"
           }

    assert presentation["trigger"] == %{
             "attrs" => %{
               "aria-controls" => "widget-placement-1-engine-warning-0-panel",
               "aria-expanded" => "false",
               "aria-haspopup" => "dialog",
               "aria-label" => "Source degraded",
               "data-overlay-trigger" => ""
             },
             "badge" => %{
               "attrs" => %{
                 "data-engine-warning" => "source_degraded",
                 "title" => "Telemetry source returned degraded data."
               },
               "class" => "badge badge-xs cursor-pointer badge-warning",
               "text" => "Source degraded"
             },
             "class" => "cadence-overlay-trigger",
             "id" => "widget-placement-1-engine-warning-0-trigger",
             "type" => "button"
           }

    assert presentation["panel"] == %{
             "attrs" => %{
               "aria-label" => "Source degraded",
               "data-overlay-panel" => "",
               "data-overlay-width" => "md"
             },
             "class" => "cadence-overlay-panel cadence-popover-panel",
             "hidden" => true,
             "id" => "widget-placement-1-engine-warning-0-panel"
           }

    body = presentation["body"]
    assert body["class"] == "p-2 text-xs"

    assert body["heading"] == %{
             "class" => "font-semibold text-base-content",
             "text" => "Source degraded"
           }

    assert body["message"] == %{
             "class" => "mt-1 text-base-content/70",
             "text" => "Telemetry source returned degraded data."
           }

    evidence_button = body["evidence_button"]
    assert evidence_button["attrs"]["phx-click"] == "open_evidence"
    assert evidence_button["attrs"]["phx-value-kind"] == "warning"
    assert evidence_button["attrs"]["phx-value-placement-id"] == "placement-1"
    assert evidence_button["attrs"]["phx-value-warning-code"] == "source_degraded"
    assert evidence_button["attrs"]["phx-value-source-request-id"] == "request-1"

    assert evidence_button == %{
             "attrs" => %{
               "data-warning-evidence-open" => "",
               "phx-click" => "open_evidence",
               "phx-value-data-source-id" => "questdb-flight",
               "phx-value-kind" => "warning",
               "phx-value-logical-source" => "simulator",
               "phx-value-placement-id" => "placement-1",
               "phx-value-realm" => "flight",
               "phx-value-source-binding-id" => "binding-flight",
               "phx-value-source-request-id" => "request-1",
               "phx-value-warning-code" => "source_degraded"
             },
             "class" => "mt-2 btn btn-xs btn-outline w-full justify-start",
             "icon" => %{
               "class" => "h-3.5 w-3.5",
               "name" => "hero-document-magnifying-glass"
             },
             "text" => "Inspect evidence",
             "type" => "button"
           }

    assert body["details"]["visible"] == true

    assert body["details"]["class"] ==
             "mt-2 grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1"

    [detail] = body["details"]["rows"]
    assert detail["value"]["attrs"]["data-warning-detail"] == "Source request"
    assert detail["value"]["text"] == "request-1"

    assert detail == %{
             "key" => "widget-placement-1-engine-warning-0-detail-0",
             "label" => %{"class" => "text-base-content/60", "text" => "Source request"},
             "value" => %{
               "attrs" => %{"data-warning-detail" => "Source request"},
               "class" => "font-mono text-base-content break-all",
               "text" => "request-1"
             }
           }

    assert body["evidence"]["visible"] == true
    assert body["evidence"]["class"] == "mt-2 space-y-1"
    assert body["evidence"]["attrs"] == %{"data-warning-evidence" => ""}

    assert body["evidence"]["heading"] == %{
             "class" => "font-semibold text-base-content/80",
             "text" => "Evidence"
           }

    assert Enum.map(body["evidence"]["rows"], & &1["key"]) == [
             "widget-placement-1-engine-warning-0-evidence-0",
             "widget-placement-1-engine-warning-0-evidence-1"
           ]

    assert Enum.map(body["evidence"]["rows"], & &1["class"]) == [
             "grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1",
             "grid grid-cols-[6rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1"
           ]

    assert Enum.map(body["evidence"]["rows"], & &1["attrs"]["data-warning-evidence-kind"]) == [
             "source",
             "frame"
           ]

    assert Enum.map(body["evidence"]["rows"], & &1["attrs"]["data-warning-evidence-id"]) == [
             "request-1",
             "frame-1"
           ]

    assert Enum.map(body["evidence"]["rows"], fn row ->
             Enum.map(row["fields"], &{&1["label"]["text"], &1["value"]["text"]})
           end) == [
             [
               {"source", "request-1"},
               {"Source", "simulator"},
               {"Observed", "2026-06-17T12:00:00Z"}
             ],
             [
               {"frame", "frame-1"},
               {"Source", "telemetry"},
               {"Observed", "2026-06-17T12:00:01Z"}
             ]
           ]

    assert body["links"]["visible"] == false
    assert body["links"]["rows"] == []
  end

  test "engine_warning_badge renders warning data links with context fallback" do
    vue =
      render_vue(
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
        })
      )

    assert_vue_host(vue, "widget-placement-1-engine-warning-0-component")
    links = vue.props["presentation"]["body"]["links"]
    assert links["visible"] == true
    assert links["class"] == "mt-2 space-y-1"
    assert links["attrs"] == %{"data-warning-links" => ""}

    assert links["heading"] == %{
             "class" => "font-semibold text-base-content/80",
             "text" => "Data links"
           }

    [explicit_context, fallback_context] = links["rows"]

    assert Enum.map(links["rows"], & &1["attrs"]["phx-click"]) == [
             "open_data_link",
             "open_data_link"
           ]

    assert Enum.map(links["rows"], & &1["attrs"]["phx-value-link-id"]) == [
             "warning-link-1",
             "warning-link-2"
           ]

    assert Enum.map(links["rows"], & &1["attrs"]["phx-value-realm"]) == [
             "simulation",
             "flight"
           ]

    assert Enum.map(links["rows"], & &1["attrs"]["phx-value-data-view"]) == [
             "all_revisions",
             "canonical"
           ]

    assert Enum.map(links["rows"], & &1["attrs"]["phx-value-time-mode"]) == [
             "replay_run",
             "wall_clock"
           ]

    assert explicit_context["attrs"] == %{
             "data-warning-link-id" => "sample-1",
             "data-warning-link-ref" => "warning-link-1",
             "data-warning-link-target" => "telemetry_sample",
             "phx-click" => "open_data_link",
             "phx-value-data-source-id" => "questdb-sim",
             "phx-value-data-view" => "all_revisions",
             "phx-value-link-id" => "warning-link-1",
             "phx-value-placement-id" => "placement-1",
             "phx-value-realm" => "simulation",
             "phx-value-replay-run-id" => "replay-1",
             "phx-value-source-binding-id" => "binding-sim",
             "phx-value-target" => "telemetry_sample",
             "phx-value-target-id" => "sample-1",
             "phx-value-time-axis" => "generation_time",
             "phx-value-time-mode" => "replay_run"
           }

    assert fallback_context["attrs"] == %{
             "data-warning-link-id" => "frame-1",
             "data-warning-link-ref" => "warning-link-2",
             "data-warning-link-target" => "telemetry_frame",
             "phx-click" => "open_data_link",
             "phx-value-data-source-id" => "questdb-flight",
             "phx-value-data-view" => "canonical",
             "phx-value-link-id" => "warning-link-2",
             "phx-value-placement-id" => "placement-1",
             "phx-value-realm" => "flight",
             "phx-value-replay-run-id" => "replay-1",
             "phx-value-source-binding-id" => "binding-flight",
             "phx-value-target" => "telemetry_frame",
             "phx-value-target-id" => "frame-1",
             "phx-value-time-axis" => "receipt_time",
             "phx-value-time-mode" => "wall_clock"
           }

    assert Enum.map(links["rows"], & &1["key"]) == [
             "widget-placement-1-engine-warning-0-link-0",
             "widget-placement-1-engine-warning-0-link-1"
           ]

    assert Enum.map(links["rows"], & &1["type"]) == ["button", "button"]

    assert Enum.map(links["rows"], & &1["class"]) == [
             "grid w-full grid-cols-[6rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left hover:border-primary/60 hover:bg-base-200",
             "grid w-full grid-cols-[6rem_minmax(0,1fr)] gap-x-2 rounded border border-base-300/70 px-2 py-1 text-left hover:border-primary/60 hover:bg-base-200"
           ]

    assert Enum.map(links["rows"], fn row ->
             Enum.map(row["fields"], &{&1["label"]["text"], &1["value"]["text"]})
           end) == [
             [{"telemetry_sample", "sample-1"}, {"Source", "telemetry"}],
             [{"telemetry_frame", "frame-1"}, {"Source", "telemetry"}]
           ]
  end

  test "warning_codes joins warning code text values" do
    assert WidgetWarningComponents.warning_codes([
             %{code_text: "source_degraded"},
             %{code_text: "late_arrival"}
           ]) == "source_degraded,late_arrival"

    assert WidgetWarningComponents.warning_codes(nil) == ""
  end

  test "DTO preserves direct and fallback HEEx attribute and body text semantics" do
    cases = [
      %{value: nil, raw: :absent, fallback: "", text: "", event: :absent},
      %{value: false, raw: :absent, fallback: "", text: "false", event: :absent},
      %{value: true, raw: "", fallback: "", text: "true", event: "true"},
      %{value: "", raw: "", fallback: "", text: "", event: :absent},
      %{value: 42, raw: "42", fallback: "42", text: "42", event: "42"}
    ]

    Enum.each(cases, fn test_case ->
      presentation =
        render_presentation(
          warning(%{
            detail_rows: [%{label: test_case.value, value: test_case.value}],
            evidence: [
              %{
                kind_text: test_case.value,
                id: test_case.value,
                source_text: test_case.value,
                observed_at_text: test_case.value
              }
            ],
            links: [
              %{
                link_id: test_case.value,
                target_text: test_case.value,
                target_id: test_case.value,
                source_text: test_case.value
              }
            ]
          })
        )

      assert presentation == Jason.decode!(Jason.encode!(presentation))
      assert presentation["body"]["details"]["visible"] == true
      assert presentation["body"]["evidence"]["visible"] == true
      assert presentation["body"]["links"]["visible"] == true

      [detail] = presentation["body"]["details"]["rows"]
      [evidence] = presentation["body"]["evidence"]["rows"]
      [link] = presentation["body"]["links"]["rows"]

      direct_attrs = [
        {detail["value"]["attrs"], "data-warning-detail"},
        {evidence["attrs"], "data-warning-evidence-kind"},
        {link["attrs"], "data-warning-link-target"}
      ]

      Enum.each(direct_attrs, fn {attrs, name} ->
        if test_case.raw == :absent do
          refute Map.has_key?(attrs, name)
        else
          assert attrs[name] == test_case.raw
        end
      end)

      assert evidence["attrs"]["data-warning-evidence-id"] == test_case.fallback
      assert link["attrs"]["data-warning-link-id"] == test_case.fallback
      assert link["attrs"]["data-warning-link-ref"] == test_case.fallback

      assert detail["label"]["text"] == test_case.text
      assert detail["value"]["text"] == test_case.text

      assert Enum.map(evidence["fields"], & &1["value"]["text"]) == [
               test_case.text,
               test_case.text,
               test_case.text
             ]

      assert Enum.map(link["fields"], &{&1["label"]["text"], &1["value"]["text"]}) == [
               {test_case.text, test_case.text},
               {"Source", test_case.text}
             ]

      for event_attr <- ["phx-value-link-id", "phx-value-target", "phx-value-target-id"] do
        if test_case.event == :absent do
          refute Map.has_key?(link["attrs"], event_attr)
        else
          assert link["attrs"][event_attr] == test_case.event
        end
      end
    end)

    empty = render_presentation(warning(%{detail_rows: [], evidence: [], links: []}))
    assert empty["body"]["details"]["visible"] == false
    assert empty["body"]["evidence"]["visible"] == false
    assert empty["body"]["links"]["visible"] == false

    assert Enum.map([:error, :warning, :info], fn severity ->
             warning(%{severity: severity})
             |> render_presentation()
             |> get_in(["trigger", "badge", "class"])
           end) == [
             "badge badge-xs cursor-pointer badge-error",
             "badge badge-xs cursor-pointer badge-warning",
             "badge badge-xs cursor-pointer badge-info"
           ]
  end

  defp render_vue(warning) do
    render_component(
      &WidgetWarningComponents.engine_warning_badge/1,
      id: "widget-placement-1-engine-warning-0",
      warning: warning,
      placement_id: "placement-1"
    )
    |> LiveVue.Test.get_vue(id: "widget-placement-1-engine-warning-0-component")
  end

  defp render_presentation(warning) do
    warning
    |> render_vue()
    |> Map.fetch!(:props)
    |> Map.fetch!("presentation")
  end

  defp assert_vue_host(vue, component_id) do
    assert vue.component == "WidgetWarning"
    assert vue.id == component_id
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
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
