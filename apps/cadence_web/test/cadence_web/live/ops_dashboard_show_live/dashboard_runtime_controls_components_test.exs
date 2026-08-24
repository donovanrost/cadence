defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponents
  alias CadenceWeb.OpsDashboardShowLive.ViewTestSupport

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

    controls = runtime_controls(html)

    assert Map.keys(controls) |> Enum.sort() == ["form", "header", "root"]

    assert Map.keys(controls["form"]) |> Enum.sort() == [
             "attrs",
             "hidden_fields",
             "markers",
             "representation",
             "semantics",
             "source"
           ]

    assert controls["root"] == %{
             "attrs" => %{
               "id" => "runtime-context-controls",
               "data-dashboard-query-control-section" => "all",
               "class" => "min-w-0"
             }
           }

    assert controls["header"] == %{
             "class" => "flex items-start justify-between gap-3",
             "copy" => %{
               "heading" => %{
                 "class" => "text-xs font-semibold text-base-content/85",
                 "text" => "Active telemetry source"
               },
               "description" => %{
                 "class" => "mt-0.5 text-[0.68rem] text-base-content/50",
                 "text" => "Defaults follow the dashboard definition. Overrides stay in the URL."
               }
             },
             "active_source" => %{
               "attrs" => %{
                 "id" => "dashboard-active-source",
                 "data-dashboard-active-data-source" => "questdb-flight",
                 "data-dashboard-active-source-binding" => "flight-binding",
                 "class" =>
                   "badge badge-primary badge-outline badge-xs max-w-64 truncate font-mono",
                 "title" => "flight-binding"
               },
               "text" => "flight-binding"
             }
           }

    assert controls["form"]["attrs"] == %{
             "id" => "runtime-context-form",
             "phx-change" => "set_runtime_context",
             "class" => "mt-3"
           }

    assert controls["form"]["hidden_fields"] == [
             hidden_field("dashboard-time-mode", "time_mode", "archive"),
             hidden_field(
               "dashboard-data-form-from",
               "from",
               "2026-06-17T12:00:00Z"
             ),
             hidden_field("dashboard-data-form-to", "to", "2026-06-17T12:05:00Z"),
             hidden_field("dashboard-replay-run-id", "replay_run_id", "")
           ]

    assert controls["form"]["source"] ==
             select_section(
               "dashboard-source-query-heading",
               "Source",
               "grid gap-2 sm:grid-cols-[9rem_minmax(0,1fr)]",
               [
                 select_field(
                   "dashboard-data-realm",
                   "realm",
                   "Realm",
                   "select-xs",
                   [{"Flight", "flight"}, {"Sim", "sim"}],
                   "flight"
                 ),
                 select_field(
                   "dashboard-source-binding",
                   "source_binding_id",
                   "Source binding",
                   "select-xs font-mono",
                   [
                     {"Primary source", ""},
                     {"flight-binding / questdb-flight", "flight-binding"}
                   ],
                   "flight-binding"
                 )
               ]
             )

    assert controls["form"]["representation"] ==
             select_section(
               "dashboard-representation-query-heading",
               "Representation",
               "grid gap-2 sm:grid-cols-2",
               [
                 select_field(
                   "dashboard-data-view",
                   "data_view",
                   "Data view",
                   "select-xs",
                   [
                     {"Canonical", "canonical"},
                     {"As recorded", "as_recorded"},
                     {"All revisions", "all_revisions"},
                     {"Recomputed", "recomputed"}
                   ],
                   "canonical"
                 ),
                 select_field(
                   "dashboard-compare-data-view",
                   "compare_data_view",
                   "Compare against",
                   "select-xs",
                   [
                     {"No compare", ""},
                     {"As recorded", "as_recorded"},
                     {"All revisions", "all_revisions"},
                     {"Recomputed", "recomputed"}
                   ],
                   ""
                 )
               ]
             )

    assert controls["form"]["semantics"] ==
             select_section(
               "dashboard-semantics-query-heading",
               "Operational semantics",
               "grid gap-2 sm:grid-cols-2",
               [
                 select_field(
                   "dashboard-time-axis",
                   "time_axis",
                   "Time basis",
                   "select-xs",
                   [{"Generation", "generation_time"}, {"Receipt", "receipt_time"}],
                   "generation_time"
                 ),
                 select_field(
                   "dashboard-limit-mode",
                   "limit_mode",
                   "Limit semantics",
                   "select-xs",
                   [
                     {"Observed", "observed"},
                     {"Current", "current"},
                     {"Recomputed", "recomputed"},
                     {"Compare", "compare"}
                   ],
                   "observed"
                 )
               ],
               %{
                 "attrs" => %{
                   "id" => "dashboard-limit-mode-fallback",
                   "data-requested-limit-mode" => "projected",
                   "data-applied-limit-mode" => "observed",
                   "data-limit-mode-fallback-reason" => "unsupported_limit_semantics_mode",
                   "class" => "badge badge-warning badge-xs mt-2 gap-1",
                   "title" => "Requested projected limit semantics; using observed."
                 },
                 "icon_class" => "hero-exclamation-triangle h-3 w-3",
                 "text" => "Observed only"
               }
             )

    assert controls["form"]["markers"] == marker_section([])

    assert ViewTestSupport.dashboard_runtime_option(
             controls,
             "dashboard-source-binding",
             "flight-binding"
           )["label"] == "flight-binding / questdb-flight"

    assert controls["header"]["active_source"]["attrs"][
             "data-dashboard-active-source-binding"
           ] == "flight-binding"

    assert controls["form"]["semantics"]["badge"]["attrs"][
             "data-requested-limit-mode"
           ] == "projected"

    for limit_mode <- ["observed", "current", "recomputed", "compare"] do
      option =
        ViewTestSupport.dashboard_runtime_option(
          controls,
          "dashboard-limit-mode",
          limit_mode
        )

      assert option["value"] == limit_mode
      refute option["disabled"]
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
        hidden_marker_categories: ["watermarks"],
        selected_data_ref: nil
      )

    controls = runtime_controls(html)
    markers = controls["form"]["markers"]

    assert markers == marker_section(["watermarks"])

    assert controls["header"]["active_source"] == %{
             "attrs" => %{
               "id" => "dashboard-active-source",
               "data-dashboard-active-data-source" => nil,
               "data-dashboard-active-source-binding" => nil,
               "class" =>
                 "badge badge-primary badge-outline badge-xs max-w-64 truncate font-mono",
               "title" => "Primary source"
             },
             "text" => "Primary source"
           }

    refute controls["form"]["semantics"]["badge"]

    refute ViewTestSupport.dashboard_runtime_control(controls, "dashboard-marker-contacts")

    assert ViewTestSupport.dashboard_runtime_control_attrs(
             ViewTestSupport.dashboard_runtime_control(controls, "dashboard-marker-limits")
           )["checked"]

    assert markers["heading"]["hidden_count"]["text"] == "1 hidden"

    for key <- [
          "limits",
          "source_status",
          "watermarks",
          "mission_events",
          "data_management"
        ] do
      assert ViewTestSupport.dashboard_runtime_control(controls, "dashboard-marker-#{key}")
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
        selected_data_ref: nil,
        section: :data
      )

    controls = runtime_controls(html)

    assert controls["root"]["attrs"] == %{
             "id" => "dashboard-data-query-controls",
             "data-dashboard-query-control-section" => "data",
             "class" => "min-w-0"
           }

    assert ViewTestSupport.dashboard_runtime_control_attrs(
             ViewTestSupport.dashboard_runtime_control(
               controls,
               "dashboard-replay-run-id"
             )
           )["value"] == "replay-run-1"
  end

  defp runtime_controls(html) do
    assert ["dashboard-runtime-controls-component"] =
             html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#dashboard-runtime-controls-component")
             |> LazyHTML.attribute("id")

    vue = LiveVue.Test.get_vue(html, id: "dashboard-runtime-controls-component")

    assert vue.component == "DashboardRuntimeControls"
    assert vue.id == "dashboard-runtime-controls-component"
    assert vue.class == "contents"
    refute vue.ssr
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["runtime_controls"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    Map.fetch!(vue.props, "runtime_controls")
  end

  defp hidden_field(id, name, value) do
    %{
      "wrapper_class" => "fieldset",
      "attrs" => %{
        "id" => id,
        "name" => name,
        "type" => "hidden",
        "value" => value,
        "required" => false,
        "disabled" => false,
        "class" => "w-full input"
      }
    }
  end

  defp select_section(heading_id, heading, fields_class, fields, badge \\ nil) do
    %{
      "attrs" => %{
        "class" => "cadence-dashboard-query-section",
        "aria-labelledby" => heading_id
      },
      "heading" => %{
        "attrs" => %{
          "id" => heading_id,
          "class" => "mb-2 text-xs font-semibold text-base-content/85"
        },
        "text" => heading
      },
      "fields_class" => fields_class,
      "fields" => fields,
      "badge" => badge
    }
  end

  defp select_field(id, name, label, class, options, selected_value) do
    %{
      "wrapper_class" => "fieldset",
      "label" => %{"class" => "hud-label block mb-1.5", "text" => label},
      "attrs" => %{
        "id" => id,
        "name" => name,
        "required" => false,
        "multiple" => false,
        "disabled" => false,
        "class" => "w-full select #{class}"
      },
      "options" =>
        Enum.map(options, fn {option_label, option_value} ->
          %{
            "label" => option_label,
            "value" => option_value,
            "selected" => option_value == selected_value,
            "disabled" => false,
            "title" => nil
          }
        end)
    }
  end

  defp marker_section(hidden_categories) do
    hidden_count = length(hidden_categories)

    %{
      "attrs" => %{
        "class" => "cadence-dashboard-query-section",
        "aria-labelledby" => "dashboard-markers-query-heading"
      },
      "heading" => %{
        "attrs" => %{
          "id" => "dashboard-markers-query-heading",
          "class" => "mb-2 text-xs font-semibold text-base-content/85"
        },
        "text" => "Chart markers",
        "hidden_count" =>
          if(hidden_count > 0,
            do: %{
              "attrs" => %{
                "id" => "dashboard-markers-hidden-count",
                "class" => "badge badge-warning badge-xs ml-1"
              },
              "text" => "#{hidden_count} hidden"
            }
          )
      },
      "toggles" => %{
        "attrs" => %{
          "id" => "dashboard-marker-toggles",
          "class" => "grid gap-1 sm:grid-cols-2"
        },
        "fields" => [
          marker_field("Limits", "limits", hidden_categories),
          marker_field("Source bindings", "source_status", hidden_categories),
          marker_field("Watermarks & gaps", "watermarks", hidden_categories),
          marker_field("Mission events", "mission_events", hidden_categories),
          marker_field("Data management", "data_management", hidden_categories)
        ]
      }
    }
  end

  defp marker_field(label, key, hidden_categories) do
    name = "markers[#{key}]"

    %{
      "wrapper_class" => "fieldset",
      "label_class" => "flex cursor-pointer items-start gap-3",
      "false_input_attrs" => %{
        "type" => "hidden",
        "name" => name,
        "value" => "false"
      },
      "input_attrs" => %{
        "type" => "checkbox",
        "id" => "dashboard-marker-#{key}",
        "name" => name,
        "value" => "true",
        "checked" => key not in hidden_categories,
        "required" => false,
        "disabled" => false,
        "class" => "checkbox checkbox-sm mt-0.5 checkbox-xs"
      },
      "label" => %{
        "class" => "block text-sm font-medium",
        "text" => label
      }
    }
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
