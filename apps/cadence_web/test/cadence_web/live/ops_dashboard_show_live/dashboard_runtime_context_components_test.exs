defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponents

  test "context_selector exposes mission, spacecraft, contact, source, ground, transport, and link results" do
    html =
      render_component(&DashboardRuntimeContextComponents.context_selector/1,
        current_mission: %{mission_id: "mission-1", display_name: "Alpha Lunar Demo"},
        spacecraft: [
          %{spacecraft_id: "spacecraft-1", display_name: "Alpha", scid: 101}
        ],
        source_endpoints: [
          %{
            source_endpoint_id: "source-endpoint-alpha",
            display_name: "Alpha Ground",
            source_ref: "gs-alpha",
            spacecraft_id: "spacecraft-1",
            metadata: %{"ground_station_id" => "dss-14"}
          }
        ],
        transports: [
          %{
            transport_id: "transport-alpha",
            display_name: "Alpha TCP",
            transport_kind: :tcp_socket,
            direction_capability: :bidirectional,
            configuration: %{
              "source_endpoint_id" => "source-endpoint-alpha",
              "ground_station_id" => "dss-14"
            }
          }
        ],
        ground_stations: [
          %{
            ground_station_id: "dss-14",
            display_name: "Alpha DSS-14",
            provider: "DSN",
            region: "goldstone"
          }
        ],
        link_assignments: [
          %{
            link_assignment_id: "link-alpha",
            spacecraft_id: "spacecraft-1",
            source_endpoint_ref: "gs-alpha",
            direction: :downlink,
            path_template_id: "path-alpha"
          }
        ],
        scheduled_contacts: [
          %{
            scheduled_contact_id: "contact-scheduled-1",
            source_endpoint_refs: ["gs-alpha"]
          }
        ],
        realized_contacts: [
          %{
            realized_contact_id: "contact-realized-1",
            scheduled_contact_id: "contact-scheduled-1",
            source_endpoint_refs: ["gs-alpha"]
          }
        ],
        context_spacecraft_id: nil,
        context_scope_kind: "contact",
        context_scope_id: "contact-realized-1",
        query: "alpha"
      )

    presentation = presentation(html)
    selected = find_node(presentation, "selected-context-label")
    clear = find_node(presentation, "selected-context-clear")
    form = find_node(presentation, "context-search-form")
    input = find_node(presentation, "context-search-input")
    results = find_node(presentation, "context-result-list")
    result_buttons = Enum.map(results["children"], &List.first(&1["children"]))

    assert presentation["tag"] == "div"
    assert presentation["attrs"] == %{"class" => "relative min-w-0"}

    assert selected["attrs"] == %{
             "id" => "dashboard-selected-context",
             "data-dashboard-selected-context-kind" => "contact",
             "data-dashboard-selected-context-id" => "contact-realized-1",
             "data-dashboard-selected-context-ids" => "",
             "class" =>
               "badge badge-primary badge-outline badge-sm mt-1 max-w-full truncate font-mono"
           }

    assert selected["children"] == ["realized / contact-realized-1 / gs-alpha"]

    assert clear["attrs"] == %{
             "type" => "button",
             "class" => "btn btn-ghost btn-xs",
             "phx-click" => "clear_context",
             "aria-label" => "Clear context"
           }

    assert find_node(clear, "selected-context-clear-icon")["attrs"] == %{
             "class" => "hero-x-mark h-3 w-3"
           }

    assert form["attrs"] == %{
             "id" => "context-search-form",
             "phx-change" => "context_search",
             "onsubmit" => "return false",
             "class" => "w-full"
           }

    assert input["attrs"] == %{
             "id" => "context-search",
             "name" => "q",
             "type" => "search",
             "value" => "alpha",
             "placeholder" =>
               "Find mission, spacecraft, contact, source, transport, ground, or link",
             "class" => "w-full input",
             "phx-debounce" => "150"
           }

    assert find_node(presentation, "context-search-fieldset")["attrs"] == %{
             "class" => "fieldset"
           }

    assert find_node(presentation, "context-search-label")["attrs"] == %{}

    assert Enum.map(result_buttons, fn button ->
             {
               button["attrs"]["phx-value-scope-kind"],
               button["attrs"]["phx-value-scope-id"],
               button["attrs"]["phx-value-scope-ids"]
             }
           end) == [
             {"contact", nil, "contact-scheduled-1,contact-realized-1"},
             {"mission", "mission-1", nil},
             {"spacecraft", "spacecraft-1", nil},
             {"contact", "contact-scheduled-1", nil},
             {"contact", "contact-realized-1", nil},
             {"source_endpoint", "source-endpoint-alpha", nil},
             {"ground_station", "dss-14", nil},
             {"transport", "transport-alpha", nil},
             {"link", "link-alpha", nil}
           ]

    result_class = "w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"

    assert Enum.map(Enum.drop(result_buttons, 1), & &1["attrs"]) == [
             %{
               "type" => "button",
               "phx-click" => "set_context",
               "phx-value-scope-kind" => "mission",
               "phx-value-scope-id" => "mission-1",
               "class" => result_class
             },
             %{
               "type" => "button",
               "phx-click" => "set_context",
               "phx-value-scope-kind" => "spacecraft",
               "phx-value-scope-id" => "spacecraft-1",
               "phx-value-spacecraft-id" => "spacecraft-1",
               "class" => result_class
             },
             %{
               "type" => "button",
               "phx-click" => "set_context",
               "phx-value-scope-kind" => "contact",
               "phx-value-scope-id" => "contact-scheduled-1",
               "data-dashboard-context-result" => "contact",
               "data-dashboard-context-contact-kind" => "scheduled",
               "data-dashboard-context-contact-id" => "contact-scheduled-1",
               "class" => result_class
             },
             %{
               "type" => "button",
               "phx-click" => "set_context",
               "phx-value-scope-kind" => "contact",
               "phx-value-scope-id" => "contact-realized-1",
               "data-dashboard-context-result" => "contact",
               "data-dashboard-context-contact-kind" => "realized",
               "data-dashboard-context-contact-id" => "contact-realized-1",
               "class" => result_class
             },
             %{
               "type" => "button",
               "phx-click" => "set_context",
               "phx-value-scope-kind" => "source_endpoint",
               "phx-value-scope-id" => "source-endpoint-alpha",
               "data-dashboard-context-result" => "source_endpoint",
               "data-dashboard-context-source-endpoint-id" => "source-endpoint-alpha",
               "class" => result_class
             },
             %{
               "type" => "button",
               "phx-click" => "set_context",
               "phx-value-scope-kind" => "ground_station",
               "phx-value-scope-id" => "dss-14",
               "data-dashboard-context-result" => "ground_station",
               "data-dashboard-context-ground-station-id" => "dss-14",
               "class" => result_class
             },
             %{
               "type" => "button",
               "phx-click" => "set_context",
               "phx-value-scope-kind" => "transport",
               "phx-value-scope-id" => "transport-alpha",
               "data-dashboard-context-result" => "transport",
               "data-dashboard-context-transport-id" => "transport-alpha",
               "class" => result_class
             },
             %{
               "type" => "button",
               "phx-click" => "set_context",
               "phx-value-scope-kind" => "link",
               "phx-value-scope-id" => "link-alpha",
               "data-dashboard-context-result" => "link",
               "data-dashboard-context-link-id" => "link-alpha",
               "class" => result_class
             }
           ]

    assert Enum.map(Enum.drop(result_buttons, 1), &List.first(&1["children"])) == [
             "Alpha Lunar Demo",
             "Alpha",
             "scheduled / contact-scheduled-1 / gs-alpha",
             "realized / contact-realized-1 / gs-alpha",
             "Alpha Ground / gs-alpha",
             "Alpha DSS-14",
             "Alpha TCP / tcp_socket",
             "spacecraft-1 / gs-alpha / downlink"
           ]

    batch = find_button(result_buttons, "data-dashboard-context-batch-result", "contact")

    assert batch["attrs"] == %{
             "type" => "button",
             "phx-click" => "set_context",
             "phx-value-scope-kind" => "contact",
             "phx-value-scope-ids" => "contact-scheduled-1,contact-realized-1",
             "data-dashboard-context-batch-result" => "contact",
             "data-dashboard-context-batch-count" => "2",
             "data-dashboard-context-batch-ids" => "contact-scheduled-1,contact-realized-1",
             "class" =>
               "mb-1 w-full rounded border border-primary/20 bg-primary/10 px-2 py-1 text-left text-sm hover:bg-primary/20"
           }

    assert find_node(batch, "batch-result-icon-contact-0")["attrs"] == %{
             "class" => "hero-squares-2x2 mr-1 inline h-3.5 w-3.5"
           }

    assert List.last(batch["children"]) == "2 contacts"

    mission = find_button(result_buttons, "phx-value-scope-kind", "mission")
    assert List.first(mission["children"]) == "Alpha Lunar Demo"

    spacecraft = find_button(result_buttons, "phx-value-scope-kind", "spacecraft")
    assert spacecraft["attrs"]["phx-value-spacecraft-id"] == "spacecraft-1"

    scheduled =
      find_button(
        result_buttons,
        "data-dashboard-context-contact-id",
        "contact-scheduled-1"
      )

    assert scheduled["attrs"]["phx-value-scope-id"] == "contact-scheduled-1"

    realized =
      find_button(result_buttons, "data-dashboard-context-contact-kind", "realized")

    assert realized["attrs"]["phx-value-scope-id"] == "contact-realized-1"
    assert List.first(realized["children"]) == "realized / contact-realized-1 / gs-alpha"

    source =
      find_button(
        result_buttons,
        "data-dashboard-context-source-endpoint-id",
        "source-endpoint-alpha"
      )

    assert source["attrs"]["phx-value-scope-kind"] == "source_endpoint"

    ground = find_button(result_buttons, "data-dashboard-context-ground-station-id", "dss-14")
    assert ground["attrs"]["phx-value-scope-kind"] == "ground_station"
    assert List.first(ground["children"]) == "Alpha DSS-14"

    transport =
      find_button(
        result_buttons,
        "data-dashboard-context-transport-id",
        "transport-alpha"
      )

    assert transport["attrs"]["phx-value-scope-kind"] == "transport"

    link = find_button(result_buttons, "data-dashboard-context-link-id", "link-alpha")
    assert link["attrs"]["phx-value-scope-kind"] == "link"
  end

  test "context_selector labels multi-select scope ids" do
    html =
      render_component(&DashboardRuntimeContextComponents.context_selector/1,
        current_mission: %{mission_id: "mission-1", display_name: "Lunar Demo"},
        spacecraft: [],
        source_endpoints: [],
        transports: [],
        ground_stations: [],
        link_assignments: [],
        scheduled_contacts: [],
        realized_contacts: [],
        context_spacecraft_id: nil,
        context_scope_kind: "source_endpoint",
        context_scope_id: "endpoint-alpha",
        context_scope_ids: ["endpoint-alpha", "endpoint-beta"],
        query: ""
      )

    presentation = presentation(html)
    selected = find_node(presentation, "selected-context-label")

    assert selected["children"] == ["2 source endpoints"]

    assert selected["attrs"] == %{
             "id" => "dashboard-selected-context",
             "data-dashboard-selected-context-kind" => "source_endpoint",
             "data-dashboard-selected-context-id" => "endpoint-alpha",
             "data-dashboard-selected-context-ids" => "endpoint-alpha,endpoint-beta",
             "class" =>
               "badge badge-primary badge-outline badge-sm mt-1 max-w-full truncate font-mono"
           }

    assert find_node(presentation, "context-result-list") == nil
  end

  test "context_selector keeps the empty query compact and omits selection and results" do
    presentation = render_selector()
    form = find_node(presentation, "context-search-form")
    input = find_node(presentation, "context-search-input")

    assert Enum.map(presentation["children"], & &1["key"]) == [
             "context-search-heading",
             "context-search-form"
           ]

    assert find_node(presentation, "selected-context-layout") == nil
    assert find_node(presentation, "selected-context-clear") == nil
    assert find_node(presentation, "context-result-list") == nil

    assert form["attrs"]["phx-change"] == "context_search"
    assert form["attrs"]["onsubmit"] == "return false"
    assert input["attrs"]["value"] == ""
    assert input["attrs"]["phx-debounce"] == "150"
  end

  test "context_selector renders the non-empty no-match state without result actions" do
    presentation = render_selector(query: "missing")
    results = find_node(presentation, "context-result-list")

    assert Enum.map(presentation["children"], & &1["key"]) == [
             "context-search-heading",
             "context-search-form",
             "context-result-list"
           ]

    assert results["attrs"] == %{
             "class" =>
               "absolute left-0 right-0 top-full z-[var(--z-popover)] mt-1 max-h-60 overflow-y-auto rounded border border-primary/20 bg-base-200 p-1 shadow-lg"
           }

    assert results["children"] == [
             %{
               "key" => "context-no-matches",
               "tag" => "li",
               "attrs" => %{"class" => "px-2 py-1 text-sm text-base-content/60"},
               "children" => ["No context matches."]
             }
           ]
  end

  test "context_selector preserves HEEx attribute and scalar body coercion" do
    presentation =
      render_selector(
        current_mission: %{mission_id: nil, display_name: "Alpha Mission"},
        spacecraft: [
          %{spacecraft_id: true, display_name: "Alpha True", scid: true},
          %{spacecraft_id: false, display_name: "Alpha False", scid: false},
          %{spacecraft_id: 7, display_name: "Alpha Seven", scid: 0}
        ],
        query: "alpha"
      )

    results = find_node(presentation, "context-result-list")
    result_buttons = Enum.map(results["children"], &List.first(&1["children"]))

    assert Enum.map(results["children"], & &1["key"]) == [
             "mission-result-",
             "spacecraft-result-true-0",
             "spacecraft-result-false-1",
             "spacecraft-result-7-2"
           ]

    [mission, true_id, false_id, numeric_id] = result_buttons

    refute Map.has_key?(mission["attrs"], "phx-value-scope-id")

    assert true_id["attrs"]["phx-value-scope-id"] == ""
    assert true_id["attrs"]["phx-value-spacecraft-id"] == ""
    assert find_node(true_id, "spacecraft-result-true-0-scid")["children"] == ["true"]

    refute Map.has_key?(false_id["attrs"], "phx-value-scope-id")
    refute Map.has_key?(false_id["attrs"], "phx-value-spacecraft-id")
    assert find_node(false_id, "spacecraft-result-false-1-scid") == nil

    assert numeric_id["attrs"]["phx-value-scope-id"] == "7"
    assert numeric_id["attrs"]["phx-value-spacecraft-id"] == "7"
    assert find_node(numeric_id, "spacecraft-result-7-2-scid")["children"] == ["0"]
  end

  defp render_selector(overrides \\ []) do
    defaults = [
      current_mission: nil,
      spacecraft: [],
      source_endpoints: [],
      transports: [],
      ground_stations: [],
      link_assignments: [],
      scheduled_contacts: [],
      realized_contacts: [],
      context_spacecraft_id: nil,
      context_scope_kind: nil,
      context_scope_id: nil,
      context_scope_ids: [],
      query: ""
    ]

    html =
      render_component(
        &DashboardRuntimeContextComponents.context_selector/1,
        Keyword.merge(defaults, overrides)
      )

    presentation(html)
  end

  defp presentation(html) do
    document = LazyHTML.from_fragment(html)
    vue = LiveVue.Test.get_vue(html, id: "dashboard-runtime-context-selector-component")

    assert document
           |> LazyHTML.query("#dashboard-runtime-context-selector-component")
           |> Enum.count() == 1

    assert vue.id == "dashboard-runtime-context-selector-component"
    assert vue.component == "DashboardRuntimeContextSelector"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert normalized_node?(vue.props["presentation"])

    vue.props["presentation"]
  end

  defp normalized_node?(%{"tag" => tag, "attrs" => attrs, "children" => children}) do
    is_binary(tag) and
      Enum.all?(attrs, fn {key, value} -> is_binary(key) and is_binary(value) end) and
      Enum.all?(children, fn
        child when is_binary(child) -> true
        child when is_map(child) -> normalized_node?(child)
        _child -> false
      end)
  end

  defp normalized_node?(_node), do: false

  defp find_node(%{"key" => key} = node, key), do: node

  defp find_node(%{"children" => children}, key) do
    Enum.find_value(children, fn
      child when is_map(child) -> find_node(child, key)
      _text -> nil
    end)
  end

  defp find_node(_node, _key), do: nil

  defp find_button(buttons, attribute, value) do
    Enum.find(buttons, &(&1["attrs"][attribute] == value))
  end
end
