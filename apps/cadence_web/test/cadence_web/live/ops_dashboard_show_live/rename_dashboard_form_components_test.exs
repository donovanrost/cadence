defmodule CadenceWeb.OpsDashboardShowLive.RenameDashboardFormComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.Document
  alias CadenceWeb.OpsDashboardShowLive.FormComponents

  test "widget_panel exposes the exact populated RenameDashboardForm contract" do
    html = render_rename_panel(%Document{name: "Power", description: "Primary EPS"})
    document = LazyHTML.from_fragment(html)

    assert document |> LazyHTML.query("#dashboard-panel-component") |> Enum.count() == 1

    assert document |> LazyHTML.query("#dashboard-panel") |> Enum.count() == 0

    assert document
           |> LazyHTML.query(~s(#dashboard-panel-component[phx-hook="VueHook"]))
           |> LazyHTML.attribute("id") == ["dashboard-panel-component"]

    assert document |> LazyHTML.query("#rename-dashboard-form-component") |> Enum.count() == 0

    assert document |> LazyHTML.query("#rename-dashboard-form") |> Enum.count() == 0

    vue = LiveVue.Test.get_vue(html, id: "dashboard-panel-component")

    assert vue.id == "dashboard-panel-component"
    assert vue.component == "DashboardPanel"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    panel = vue.props["presentation"]

    assert panel["sheet"] == %{
             "layer" => %{
               "attrs" => %{
                 "class" => "cadence-sheet-layer",
                 "id" => "dashboard-panel-layer"
               }
             },
             "root" => %{
               "attrs" => %{
                 "aria-label" => "Rename Dashboard",
                 "aria-modal" => "false",
                 "class" => "cadence-sheet",
                 "data-sheet-width" => "md",
                 "id" => "dashboard-panel",
                 "phx-key" => "Escape",
                 "phx-window-keydown" => "close_panel",
                 "role" => "dialog"
               }
             },
             "header" => %{
               "attrs" => %{"class" => "cadence-sheet-header"},
               "title" => %{
                 "attrs" => %{"class" => "hud-label"},
                 "text" => "Rename Dashboard"
               },
               "close" => %{
                 "attrs" => %{
                   "aria-label" => "Close panel",
                   "class" => "cadence-icon-button",
                   "phx-click" => "close_panel",
                   "type" => "button"
                 },
                 "icon" => %{
                   "attrs" => %{"class" => "hero-x-mark h-4 w-4"}
                 }
               }
             },
             "body" => %{"attrs" => %{"class" => "cadence-sheet-body"}}
           }

    assert panel["child"]["kind"] == "rename_dashboard_form"

    assert panel["child"]["wrapper"] == %{
             "attrs" => %{
               "class" => "contents",
               "id" => "rename-dashboard-form-component"
             }
           }

    assert panel["child"]["outer_wrapper"] == nil

    assert panel["child"]["presentation"] == %{
             "root" => %{
               "attrs" => %{
                 "class" => "space-y-4",
                 "id" => "rename-dashboard-form",
                 "phx-submit" => "rename"
               },
               "param" => "dashboard",
               "params" => %{
                 "description" => "Primary EPS",
                 "name" => "Power"
               }
             },
             "fields" => [
               text_field("name", "dashboard[name]", "Name", "Power", true),
               text_field(
                 "description",
                 "dashboard[description]",
                 "Description",
                 "Primary EPS",
                 false
               )
             ],
             "submit" => %{
               "attrs" => %{"class" => "btn btn-primary", "type" => "submit"},
               "text" => "Save"
             }
           }
  end

  test "widget_panel preserves nil description presentation and browser form semantics" do
    presentation =
      %Document{name: "Power", description: nil}
      |> render_rename_panel()
      |> LiveVue.Test.get_vue(id: "dashboard-panel-component")
      |> Map.fetch!(:props)
      |> Map.fetch!("presentation")
      |> Map.fetch!("child")
      |> Map.fetch!("presentation")

    assert presentation["root"]["params"] == %{
             "name" => "Power",
             "description" => ""
           }

    assert Enum.map(presentation["fields"], & &1["key"]) == ["name", "description"]

    assert field(presentation, "name")["control"]["value"] == "Power"
    assert field(presentation, "description")["control"]["value"] == nil

    assert field(presentation, "name")["control"]["attrs"]["required"] == ""
    refute Map.has_key?(field(presentation, "description")["control"]["attrs"], "required")
  end

  defp render_rename_panel(document) do
    empty_form = Phoenix.Component.to_form(%{}, as: :unused)

    render_component(&FormComponents.widget_panel/1,
      panel: :rename,
      form: empty_form,
      section_form: empty_form,
      spacecraft: [],
      operational_observables: [],
      filtered_points: [],
      filtered_operational_observables: [],
      points_empty?: true,
      selected_point: nil,
      selected_points: [],
      selected_operational_observables: [],
      dashboard_scope_context: nil,
      error: "",
      mission_id: "mission-1",
      dashboard_document: document,
      dashboard_summary: nil,
      dashboard_versions: [],
      dashboard_lifecycle_events: [],
      dashboard_comparison_review_queue: %{},
      runtime_diagnostics: %{},
      dashboard_current_path: "/missions/mission-1/ops/dashboards/dashboard-1/edit",
      historical_workflow_request_form: empty_form
    )
  end

  defp text_field(key, name, label, value, required?) do
    attrs = %{
      "class" => "w-full input",
      "name" => name,
      "type" => "text"
    }

    attrs = if required?, do: Map.put(attrs, "required", ""), else: attrs

    %{
      "key" => key,
      "wrapper" => %{"attrs" => %{"class" => "fieldset mb-3"}},
      "label" => %{
        "attrs" => %{"class" => "hud-label block mb-1.5"},
        "text" => label
      },
      "control" => %{"attrs" => attrs, "value" => value}
    }
  end

  defp field(presentation, key) do
    Enum.find(presentation["fields"], &(&1["key"] == key))
  end
end
