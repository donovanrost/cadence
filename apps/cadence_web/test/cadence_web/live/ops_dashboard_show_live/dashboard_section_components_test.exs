defmodule CadenceWeb.OpsDashboardShowLive.DashboardSectionComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Dashboards.{Document, Section}
  alias CadenceWeb.OpsDashboardShowLive.DashboardSectionComponents

  test "section_manager exposes the ordered section list and exact action contract" do
    manager =
      section_manager_presentation([
        %Section{
          section_id: "power",
          title: "Power",
          description: "Primary bus",
          collapsed_by_default?: true
        },
        %Section{
          section_id: "thermal",
          title: "Thermal",
          description: nil,
          collapsed_by_default?: false
        },
        %Section{
          section_id: "comms",
          title: "Communications",
          description: "",
          collapsed_by_default?: false
        }
      ])

    assert manager |> Map.keys() |> Enum.sort() == ~w(form root section_list)
    assert manager["root"] == %{"attrs" => %{"class" => "space-y-5"}}

    presentation = manager["section_list"]

    assert presentation |> Map.keys() |> Enum.sort() == ~w(empty root sections)

    assert presentation["root"] == %{
             "attrs" => %{"class" => "space-y-2", "id" => "dashboard-section-list"}
           }

    assert presentation["empty"] == %{
             "attrs" => %{"class" => "text-sm text-base-content/60"},
             "text" => "No sections yet. Existing widgets remain in the unsectioned canvas.",
             "visible" => false
           }

    [power, thermal, communications] = presentation["sections"]

    assert Enum.map(presentation["sections"], fn section ->
             {section["key"], section["order"], section["attrs"]}
           end) == [
             {
               "dashboard-section-power",
               0,
               %{
                 "class" => "rounded border border-base-300/60 bg-base-200/35 p-3",
                 "data-dashboard-section" => "power",
                 "id" => "dashboard-section-power"
               }
             },
             {
               "dashboard-section-thermal",
               1,
               %{
                 "class" => "rounded border border-base-300/60 bg-base-200/35 p-3",
                 "data-dashboard-section" => "thermal",
                 "id" => "dashboard-section-thermal"
               }
             },
             {
               "dashboard-section-comms",
               2,
               %{
                 "class" => "rounded border border-base-300/60 bg-base-200/35 p-3",
                 "data-dashboard-section" => "comms",
                 "id" => "dashboard-section-comms"
               }
             }
           ]

    assert power["layout"] == %{"attrs" => %{"class" => "flex items-start gap-2"}}

    assert Enum.map(presentation["sections"], & &1["icon"]) ==
             List.duplicate(
               %{
                 "attrs" => %{
                   "class" => "hero-rectangle-group mt-0.5 h-4 w-4 text-primary"
                 }
               },
               3
             )

    assert power["content"] == %{
             "attrs" => %{"class" => "min-w-0 flex-1"},
             "default_state" => %{
               "attrs" => %{
                 "class" => "mt-1 inline-flex font-mono text-[0.65rem] text-base-content/45"
               },
               "text" => "Collapsed by default"
             },
             "description" => %{
               "attrs" => %{"class" => "mt-0.5 text-xs text-base-content/55"},
               "text" => "Primary bus",
               "visible" => true
             },
             "title" => %{
               "attrs" => %{"class" => "font-medium"},
               "text" => "Power"
             }
           }

    assert Enum.map(presentation["sections"], fn section ->
             {
               section["content"]["title"]["text"],
               section["content"]["description"]["text"],
               section["content"]["description"]["visible"],
               section["content"]["default_state"]["text"]
             }
           end) == [
             {"Power", "Primary bus", true, "Collapsed by default"},
             {"Thermal", "", false, "Open by default"},
             {"Communications", "", true, "Open by default"}
           ]

    assert thermal["actions"]["attrs"] == %{"class" => "flex gap-1"}

    assert thermal["actions"]["buttons"] == [
             %{
               "attrs" => %{
                 "aria-label" => "Move Thermal up",
                 "class" => "btn btn-ghost btn-xs btn-square",
                 "phx-click" => "move_dashboard_section",
                 "phx-value-direction" => "up",
                 "phx-value-section-id" => "thermal",
                 "type" => "button"
               },
               "icon" => %{"attrs" => %{"class" => "hero-arrow-up h-3.5 w-3.5"}},
               "key" => "move-up"
             },
             %{
               "attrs" => %{
                 "aria-label" => "Move Thermal down",
                 "class" => "btn btn-ghost btn-xs btn-square",
                 "phx-click" => "move_dashboard_section",
                 "phx-value-direction" => "down",
                 "phx-value-section-id" => "thermal",
                 "type" => "button"
               },
               "icon" => %{"attrs" => %{"class" => "hero-arrow-down h-3.5 w-3.5"}},
               "key" => "move-down"
             },
             %{
               "attrs" => %{
                 "aria-label" => "Edit Thermal",
                 "class" => "btn btn-ghost btn-xs btn-square",
                 "phx-click" => "edit_dashboard_section",
                 "phx-value-section-id" => "thermal",
                 "type" => "button"
               },
               "icon" => %{
                 "attrs" => %{"class" => "hero-pencil-square h-3.5 w-3.5"}
               },
               "key" => "edit"
             },
             %{
               "attrs" => %{
                 "aria-label" => "Remove Thermal",
                 "class" => "btn btn-ghost btn-xs btn-square text-error",
                 "data-confirm" =>
                   "Remove this section? Its widgets will move to the unsectioned canvas.",
                 "phx-click" => "remove_dashboard_section",
                 "phx-value-section-id" => "thermal",
                 "type" => "button"
               },
               "icon" => %{"attrs" => %{"class" => "hero-trash h-3.5 w-3.5"}},
               "key" => "remove"
             }
           ]

    assert action(power, "move-up")["attrs"]["disabled"] == ""
    refute Map.has_key?(action(power, "move-down")["attrs"], "disabled")
    refute Map.has_key?(action(thermal, "move-up")["attrs"], "disabled")
    refute Map.has_key?(action(thermal, "move-down")["attrs"], "disabled")
    refute Map.has_key?(action(communications, "move-up")["attrs"], "disabled")
    assert action(communications, "move-down")["attrs"]["disabled"] == ""

    assert manager["form"] == %{
             "root" => %{
               "attrs" => %{
                 "class" => "space-y-3 border-t border-base-300/60 pt-4",
                 "id" => "dashboard-section-form",
                 "phx-change" => "validate_dashboard_section",
                 "phx-submit" => "save_dashboard_section"
               },
               "param" => "section",
               "params" => %{
                 "collapsed_by_default" => "false",
                 "description" => "",
                 "section_id" => "",
                 "title" => ""
               }
             },
             "section_id" => %{
               "attrs" => %{
                 "name" => "section[section_id]",
                 "type" => "hidden",
                 "value" => ""
               }
             },
             "heading" => %{
               "attrs" => %{"class" => "hud-label"},
               "text" => "Add section"
             },
             "title" => %{
               "wrapper" => %{"attrs" => %{"class" => "fieldset mb-3"}},
               "label" => %{
                 "attrs" => %{"class" => "hud-label block mb-1.5"},
                 "text" => "Title"
               },
               "control" => %{
                 "attrs" => %{
                   "class" => "w-full input",
                   "id" => "section_title",
                   "name" => "section[title]",
                   "required" => "",
                   "type" => "text",
                   "value" => ""
                 }
               },
               "errors" => []
             },
             "description" => %{
               "wrapper" => %{"attrs" => %{"class" => "fieldset mb-3"}},
               "label" => %{
                 "attrs" => %{"class" => "hud-label block mb-1.5"},
                 "text" => "Description"
               },
               "control" => %{
                 "attrs" => %{
                   "class" => "w-full textarea",
                   "id" => "section_description",
                   "name" => "section[description]"
                 },
                 "text" => ""
               },
               "errors" => []
             },
             "collapsed_by_default" => %{
               "wrapper" => %{"attrs" => %{"class" => "fieldset mb-3"}},
               "label" => %{
                 "attrs" => %{"class" => "flex cursor-pointer items-start gap-3"}
               },
               "hidden_control" => %{
                 "attrs" => %{
                   "name" => "section[collapsed_by_default]",
                   "type" => "hidden",
                   "value" => "false"
                 }
               },
               "control" => %{
                 "attrs" => %{
                   "class" => "checkbox checkbox-sm mt-0.5",
                   "id" => "section_collapsed_by_default",
                   "name" => "section[collapsed_by_default]",
                   "type" => "checkbox",
                   "value" => "true"
                 }
               },
               "text" => %{
                 "wrapper" => %{"attrs" => %{}},
                 "label" => %{
                   "attrs" => %{"class" => "block text-sm font-medium"},
                   "text" => "Collapse by default for operators"
                 }
               }
             },
             "error" => nil,
             "actions" => %{
               "attrs" => %{"class" => "flex gap-2"},
               "save" => %{
                 "attrs" => %{
                   "class" => "btn btn-primary btn-sm",
                   "id" => "save-dashboard-section",
                   "type" => "submit"
                 },
                 "text" => "Add section"
               },
               "cancel" => %{
                 "attrs" => %{
                   "class" => "btn btn-ghost btn-sm",
                   "phx-click" => "open_dashboard_sections",
                   "type" => "button"
                 },
                 "text" => "Cancel",
                 "visible" => false
               }
             }
           }
  end

  test "section_manager exposes the empty state and disables both moves for one section" do
    empty = section_manager_presentation([])["section_list"]

    assert empty["sections"] == []

    assert empty["empty"] == %{
             "attrs" => %{"class" => "text-sm text-base-content/60"},
             "text" => "No sections yet. Existing widgets remain in the unsectioned canvas.",
             "visible" => true
           }

    manager =
      section_manager_presentation(
        [
          %Section{
            section_id: "only",
            title: "Only section",
            description: nil,
            collapsed_by_default?: false
          }
        ],
        params: %{
          "section_id" => "only",
          "title" => "Only section",
          "description" => "Primary channel",
          "collapsed_by_default" => "true"
        },
        error: "Section title must be 1 to 80 characters."
      )

    single = manager["section_list"]

    assert single["empty"]["visible"] == false
    assert [section] = single["sections"]
    assert action(section, "move-up")["attrs"]["disabled"] == ""
    assert action(section, "move-down")["attrs"]["disabled"] == ""
    refute Map.has_key?(action(section, "edit")["attrs"], "disabled")
    refute Map.has_key?(action(section, "remove")["attrs"], "disabled")

    form = manager["form"]

    assert form["root"]["params"] == %{
             "collapsed_by_default" => "true",
             "description" => "Primary channel",
             "section_id" => "only",
             "title" => "Only section"
           }

    assert form["section_id"]["attrs"]["value"] == "only"
    assert form["heading"]["text"] == "Edit section"
    assert form["title"]["control"]["attrs"]["value"] == "Only section"
    assert form["description"]["control"]["text"] == "Primary channel"
    assert form["collapsed_by_default"]["control"]["attrs"]["checked"] == ""

    assert form["error"] == %{
             "attrs" => %{"class" => "text-sm text-error"},
             "text" => "Section title must be 1 to 80 characters."
           }

    assert form["actions"]["save"]["text"] == "Save section"

    assert form["actions"]["cancel"] == %{
             "attrs" => %{
               "class" => "btn btn-ghost btn-sm",
               "phx-click" => "open_dashboard_sections",
               "type" => "button"
             },
             "text" => "Cancel",
             "visible" => true
           }
  end

  test "section_manager preserves raw HEEx attribute body and truthiness semantics" do
    values = [nil, false, true, "", 7]
    expected_body = ["", "false", "true", "", "7"]
    expected_direct_attr = [:omitted, :omitted, "", "", "7"]
    expected_truth = [false, false, true, true, true]

    Enum.zip([values, expected_body, expected_direct_attr, expected_truth])
    |> Enum.each(fn {value, body, direct_attr, truthy?} ->
      presentation =
        section_manager_presentation([
          %Section{
            section_id: value,
            title: value,
            description: value,
            collapsed_by_default?: value
          }
        ])["section_list"]

      assert [section] = presentation["sections"]
      assert section["key"] == "dashboard-section-#{body}"
      assert section["attrs"]["id"] == "dashboard-section-#{body}"
      assert section["content"]["title"]["text"] == body
      assert section["content"]["description"]["text"] == body
      assert section["content"]["description"]["visible"] == truthy?

      assert section["content"]["default_state"]["text"] ==
               if(truthy?, do: "Collapsed by default", else: "Open by default")

      for action_key <- ~w(move-up move-down edit remove) do
        attrs = action(section, action_key)["attrs"]

        if direct_attr == :omitted do
          refute Map.has_key?(attrs, "phx-value-section-id")
        else
          assert attrs["phx-value-section-id"] == direct_attr
        end
      end

      if direct_attr == :omitted do
        refute Map.has_key?(section["attrs"], "data-dashboard-section")
      else
        assert section["attrs"]["data-dashboard-section"] == direct_attr
      end

      assert action(section, "move-up")["attrs"]["aria-label"] == "Move #{body} up"
      assert action(section, "move-down")["attrs"]["aria-label"] == "Move #{body} down"
      assert action(section, "edit")["attrs"]["aria-label"] == "Edit #{body}"
      assert action(section, "remove")["attrs"]["aria-label"] == "Remove #{body}"
      assert action(section, "move-up")["attrs"]["disabled"] == ""
      assert action(section, "move-down")["attrs"]["disabled"] == ""
    end)

    nil_description =
      section_manager_presentation([],
        params: %{
          "section_id" => "",
          "title" => "",
          "description" => nil,
          "collapsed_by_default" => "false"
        }
      )

    newline_description =
      section_manager_presentation([],
        params: %{
          "section_id" => "",
          "title" => "",
          "description" => "\nLeading newline",
          "collapsed_by_default" => "false"
        }
      )

    assert nil_description["form"]["description"]["control"]["text"] == ""

    assert newline_description["form"]["description"]["control"]["text"] ==
             "\nLeading newline"
  end

  defp section_manager_presentation(sections, options \\ []) do
    params =
      Keyword.get(options, :params, %{
        "section_id" => "",
        "title" => "",
        "description" => "",
        "collapsed_by_default" => "false"
      })

    html =
      render_component(&DashboardSectionComponents.section_manager/1,
        document: %Document{sections: sections},
        form: Phoenix.Component.to_form(params, as: :section),
        error: Keyword.get(options, :error)
      )

    vue = LiveVue.Test.get_vue(html, id: "dashboard-section-manager-component")

    assert vue.id == "dashboard-section-manager-component"
    assert vue.component == "DashboardSectionManager"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))

    vue.props["presentation"]
  end

  defp action(section, key) do
    Enum.find(section["actions"]["buttons"], &(&1["key"] == key))
  end
end
