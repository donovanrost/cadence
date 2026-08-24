defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDiagnosticsPanelComponents

  test "diagnostics_panel renders runtime attributes and row sections" do
    html =
      render_component(&RuntimeDiagnosticsPanelComponents.diagnostics_panel/1,
        diagnostics: diagnostics()
      )

    document = LazyHTML.from_fragment(html)

    assert ["3"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-invalidation-events")

    assert ["settled"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-status")

    assert ["obsolete-1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-ignored-resolve-ids")

    assert ["live_tick:tick:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-coalesced")

    assert ["live_tick:edit_mode:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-noops")

    assert ["resolve_failed:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-refresh-failures")

    assert ["telemetry:request-1:source_degraded"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-source-execution-degraded-identities")

    assert ["fallback:1 native:1"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-source-capability-statuses")

    assert ["telemetry:request-1:fallback:generation_time->receipt_time"] =
             document
             |> LazyHTML.query("#dashboard-diagnostics-panel")
             |> LazyHTML.attribute("data-runtime-source-capability-postures")

    engine =
      diagnostics_section_presentation(html, "dashboard-diagnostics-engine-section-component")

    runtime =
      diagnostics_section_presentation(html, "dashboard-diagnostics-runtime-section-component")

    invalidation =
      diagnostics_section_presentation(html, "dashboard-diagnostics-invalidation-section-component")

    assert "context_change" = diagnostics_row_body(engine, "Resolve")

    assert "accept_result" = diagnostics_row_body(runtime, "Visible action")

    assert "live_tick:tick:1" = diagnostics_row_body(runtime, "Refresh coalesced")

    assert "resolve_failed:1" = diagnostics_row_body(runtime, "Refresh failures")

    assert "source:2" = diagnostics_row_body(invalidation, "Boundaries")
  end

  test "diagnostics sections expose exact non-SSR LiveVue host and presentation contracts" do
    html =
      render_component(&RuntimeDiagnosticsPanelComponents.diagnostics_panel/1,
        diagnostics: diagnostics()
      )

    document = LazyHTML.from_fragment(html)

    host_ids = [
      "dashboard-diagnostics-engine-section-component",
      "dashboard-diagnostics-runtime-section-component",
      "dashboard-diagnostics-invalidation-section-component"
    ]

    vues = Enum.map(host_ids, &LiveVue.Test.get_vue(html, id: &1))

    assert host_ids ==
             document
             |> LazyHTML.query(
               ~s([id^="dashboard-diagnostics-"][id$="-section-component"])
             )
             |> LazyHTML.attribute("id")

    assert Enum.map(vues, & &1.id) == host_ids
    assert Enum.uniq(Enum.map(vues, & &1.id)) == host_ids
    assert Enum.map(vues, & &1.component) == List.duplicate("RuntimeDiagnosticsSection", 3)
    assert Enum.map(vues, & &1.ssr) == [false, false, false]
    assert Enum.map(vues, & &1.class) == ["contents", "contents", "contents"]
    assert Enum.map(vues, & &1.handlers) == [%{}, %{}, %{}]
    assert Enum.map(vues, & &1.slots) == [%{}, %{}, %{}]
    assert Enum.all?(vues, &(Map.keys(&1.props) == ["presentation"]))
    assert Enum.all?(vues, &(&1.props == Jason.decode!(Jason.encode!(&1.props))))

    [engine, runtime, invalidation] = Enum.map(vues, & &1.props["presentation"])

    assert engine ==
             expected_section("Engine", [
               {"Resolve", "context_change"},
               {"Source requests", "3"}
             ])

    assert runtime ==
             expected_section("Runtime", [
               {"Visible action", "accept_result"},
               {"Refresh coalesced", "live_tick:tick:1"},
               {"Refresh failures", "resolve_failed:1"},
               {"Source runtime actions", "refresh_source_result:2"}
             ])

    assert invalidation ==
             expected_section("Invalidation", [
               {"Boundaries", "source:2"},
               {"Context matches", "2"}
             ])

    assert LiveVue.Test.get_vue(html, id: "dashboard-recent-invalidations-component").component ==
             "RuntimeRecentInvalidations"
  end

  test "diagnostics section DTO preserves scalar HEEx body semantics and remains JSON-total" do
    html =
      render_component(&RuntimeDiagnosticsPanelComponents.diagnostics_panel/1,
        diagnostics:
          diagnostics(%{
            engine_rows: [
              %{label: "Nil", value: nil},
              %{label: "True", value: true},
              %{label: "False", value: false},
              %{label: "Integer", value: 42},
              %{label: "Atom", value: :settled}
            ]
          })
      )

    vue = LiveVue.Test.get_vue(html, id: "dashboard-diagnostics-engine-section-component")
    presentation = vue.props["presentation"]

    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    assert Enum.map(presentation["rows"]["items"], fn row ->
             {row["label"]["body"], row["value"]["body"]}
           end) == [
             {"Nil", ""},
             {"True", "true"},
             {"False", "false"},
             {"Integer", "42"},
             {"Atom", "settled"}
           ]
  end

  defp diagnostics(overrides \\ %{}) do
    Map.merge(
      %{
        invalidation_event_count: 3,
        invalidation_artifact_count: 4,
        invalidation_boundary_summary: "source:2",
        invalidation_context_match_count: 2,
        invalidation_context_filtered_count: 1,
        invalidation_context_filter_reasons: "scope_mismatch:1",
        invalidation_refresh_allowed_count: 1,
        invalidation_refresh_suppressed_count: 2,
        invalidation_refresh_suppress_reasons: "scope_mismatch:2",
        refresh_status: "settled",
        refresh_reason: "accepted",
        active_refresh_mode: "-",
        active_refresh_started_at: "-",
        visible_refresh_action: "accept_result",
        last_refresh_started_at: "2026-06-26T17:00:00Z",
        last_refresh_finished_at: "2026-06-26T17:00:01Z",
        last_refresh_duration_ms: "12",
        refresh_starts: "live_tick:1",
        refresh_cancellations: "-",
        refresh_coalesced: "live_tick:tick:1",
        refresh_noops: "live_tick:edit_mode:1",
        refresh_failures: "resolve_failed:1",
        refresh_ignored: "obsolete_resolve:1",
        refresh_ignored_resolve_ids: "obsolete-1",
        canceled_resolve_count: "0",
        failed_resolve_count: "0",
        source_execution_degraded_identities: "telemetry:request-1:source_degraded",
        source_execution_degraded_actions: "telemetry:request-1:wait_for_refresh:inspect_source",
        source_capability_statuses_text: "fallback:1 native:1",
        source_capability_posture_text:
          "telemetry:request-1:fallback:generation_time->receipt_time",
        source_capability_postures: [],
        engine_rows: [
          %{label: "Resolve", value: "context_change"},
          %{label: "Source requests", value: "3"}
        ],
        runtime_rows: [
          %{label: "Visible action", value: "accept_result"},
          %{label: "Refresh coalesced", value: "live_tick:tick:1"},
          %{label: "Refresh failures", value: "resolve_failed:1"},
          %{label: "Source runtime actions", value: "refresh_source_result:2"}
        ],
        invalidation_rows: [
          %{label: "Boundaries", value: "source:2"},
          %{label: "Context matches", value: "2"}
        ],
        cache_summary: %{visible?: false},
        source_execution_degraded_summary: %{visible?: false},
        source_execution_degraded_drilldowns: [],
        source_dependency_evidence: [],
        source_dependency_evidence_text: "-",
        source_dependency_degraded_count: 0,
        no_refresh_summary: %{visible?: false},
        recent_invalidations: []
      },
      overrides
    )
  end

  defp diagnostics_section_presentation(html, id) do
    html
    |> LiveVue.Test.get_vue(id: id)
    |> Map.fetch!(:props)
    |> Map.fetch!("presentation")
  end

  defp diagnostics_row_body(presentation, label) do
    presentation["rows"]["items"]
    |> Enum.find(&(&1["label"]["body"] == label))
    |> Map.fetch!("value")
    |> Map.fetch!("body")
  end

  defp expected_section(title, rows) do
    %{
      "root" => %{
        "tag" => "section",
        "class" => "space-y-2",
        "attrs" => %{"data-diagnostics-section" => title}
      },
      "title" => %{
        "tag" => "h3",
        "class" => "hud-label",
        "attrs" => %{},
        "body" => title
      },
      "rows" => %{
        "tag" => "dl",
        "class" => "grid grid-cols-[7rem_minmax(0,1fr)] gap-x-2 gap-y-1 text-xs",
        "attrs" => %{},
        "items" =>
          rows
          |> Enum.with_index()
          |> Enum.map(fn {{label, value}, index} ->
            %{
              "key" => index,
              "label" => %{
                "tag" => "dt",
                "class" => "text-base-content/60",
                "attrs" => %{},
                "body" => label
              },
              "value" => %{
                "tag" => "dd",
                "class" => "font-mono text-base-content break-all",
                "attrs" => %{"data-diagnostics-field" => label},
                "body" => value
              }
            }
          end)
      }
    }
  end
end
