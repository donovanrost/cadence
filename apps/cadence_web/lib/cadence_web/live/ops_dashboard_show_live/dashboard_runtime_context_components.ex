defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextPresentation

  attr(:current_mission, :any, default: nil)
  attr(:spacecraft, :list, required: true)
  attr(:source_endpoints, :list, default: [])
  attr(:transports, :list, default: [])
  attr(:ground_stations, :list, default: [])
  attr(:link_assignments, :list, default: [])
  attr(:scheduled_contacts, :list, default: [])
  attr(:realized_contacts, :list, default: [])
  attr(:context_spacecraft_id, :string, required: true)
  attr(:context_scope_kind, :string, default: nil)
  attr(:context_scope_id, :string, default: nil)
  attr(:context_scope_ids, :list, default: [])
  attr(:query, :string, required: true)

  def context_selector(assigns) do
    assigns =
      assign(
        assigns,
        :context_selector_presentation,
        context_selector_presentation(assigns)
      )

    ~H"""
    <.vue
      id="dashboard-runtime-context-selector-component"
      v-component="DashboardRuntimeContextSelector"
      presentation={@context_selector_presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def context_selector_presentation(assigns) do
    context_presentation = DashboardRuntimeContextPresentation.build(assigns)

    node(
      "context-selector-root",
      "div",
      %{"class" => "relative min-w-0"},
      selected_context_nodes(context_presentation) ++
        [context_search_heading(), context_search_form(assigns.query)] ++
        context_result_list_nodes(context_presentation, assigns.query)
    )
  end

  defp selected_context_nodes(%{selected_label: selected_label} = presentation) do
    if truthy?(selected_label) do
      [
        node(
          "selected-context-layout",
          "div",
          %{"class" => "mb-3 flex items-center justify-between gap-3"},
          [
            node("selected-context-content", "div", %{"class" => "min-w-0"}, [
              node(
                "selected-context-heading",
                "p",
                %{
                  "class" =>
                    "text-[0.62rem] font-semibold uppercase tracking-[0.08em] text-base-content/45"
                },
                ["Current scope"]
              ),
              node(
                "selected-context-label",
                "span",
                %{
                  "id" => "dashboard-selected-context",
                  "data-dashboard-selected-context-kind" =>
                    presentation.selected_scope_kind || "",
                  "data-dashboard-selected-context-id" => presentation.selected_scope_id || "",
                  "data-dashboard-selected-context-ids" =>
                    Enum.join(presentation.selected_scope_ids, ","),
                  "class" =>
                    "badge badge-primary badge-outline badge-sm mt-1 max-w-full truncate font-mono"
                },
                [selected_label]
              )
            ]),
            node(
              "selected-context-clear",
              "button",
              %{
                "type" => "button",
                "class" => "btn btn-ghost btn-xs",
                "phx-click" => "clear_context",
                "aria-label" => "Clear context"
              },
              [
                node(
                  "selected-context-clear-icon",
                  "span",
                  %{"class" => "hero-x-mark h-3 w-3"},
                  []
                )
              ]
            )
          ]
        )
      ]
    else
      []
    end
  end

  defp context_search_heading do
    node(
      "context-search-heading",
      "p",
      %{
        "class" =>
          "mb-1.5 text-[0.62rem] font-semibold uppercase tracking-[0.08em] text-base-content/45"
      },
      ["Find operational context"]
    )
  end

  defp context_search_form(query) do
    node(
      "context-search-form",
      "form",
      %{
        "id" => "context-search-form",
        "phx-change" => "context_search",
        "onsubmit" => "return false",
        "class" => "w-full"
      },
      [
        node("context-search-fieldset", "div", %{"class" => "fieldset"}, [
          node("context-search-label", "label", %{}, [
            node(
              "context-search-input",
              "input",
              %{
                "id" => "context-search",
                "name" => "q",
                "type" => "search",
                "value" => query,
                "placeholder" =>
                  "Find mission, spacecraft, contact, source, transport, ground, or link",
                "class" => "w-full input",
                "phx-debounce" => "150"
              },
              []
            )
          ])
        ])
      ]
    )
  end

  defp context_result_list_nodes(_presentation, ""), do: []

  defp context_result_list_nodes(presentation, _query) do
    children =
      batch_action_nodes(presentation.batch_actions) ++
        mission_result_nodes(presentation.mission) ++
        spacecraft_result_nodes(presentation.spacecraft) ++
        contact_result_nodes(presentation.contacts) ++
        resource_result_nodes(
          presentation.source_endpoints,
          "source-endpoint",
          "source_endpoint",
          "source endpoint",
          "data-dashboard-context-source-endpoint-id"
        ) ++
        resource_result_nodes(
          presentation.ground_stations,
          "ground-station",
          "ground_station",
          "ground station",
          "data-dashboard-context-ground-station-id"
        ) ++
        resource_result_nodes(
          presentation.transports,
          "transport",
          "transport",
          "transport",
          "data-dashboard-context-transport-id"
        ) ++
        resource_result_nodes(
          presentation.links,
          "link",
          "link",
          "link",
          "data-dashboard-context-link-id"
        ) ++ no_matches_nodes(Map.get(presentation, :no_matches?))

    [
      node(
        "context-result-list",
        "ul",
        %{
          "class" =>
            "absolute left-0 right-0 top-full z-[var(--z-popover)] mt-1 max-h-60 overflow-y-auto rounded border border-primary/20 bg-base-200 p-1 shadow-lg"
        },
        children
      )
    ]
  end

  defp batch_action_nodes(actions) do
    actions
    |> Enum.with_index()
    |> Enum.map(fn {action, index} ->
      node("batch-result-#{action.scope_kind}-#{index}", "li", %{}, [
        node(
          "batch-result-button-#{action.scope_kind}-#{index}",
          "button",
          %{
            "type" => "button",
            "phx-click" => "set_context",
            "phx-value-scope-kind" => action.scope_kind,
            "phx-value-scope-ids" => action.scope_ids_text,
            "data-dashboard-context-batch-result" => action.scope_kind,
            "data-dashboard-context-batch-count" => action.count,
            "data-dashboard-context-batch-ids" => action.scope_ids_text,
            "class" =>
              "mb-1 w-full rounded border border-primary/20 bg-primary/10 px-2 py-1 text-left text-sm hover:bg-primary/20"
          },
          [
            node(
              "batch-result-icon-#{action.scope_kind}-#{index}",
              "span",
              %{"class" => "hero-squares-2x2 mr-1 inline h-3.5 w-3.5"},
              []
            ),
            action.label
          ]
        )
      ])
    end)
  end

  defp mission_result_nodes(mission) when mission in [nil, false], do: []

  defp mission_result_nodes(mission) do
    [
      node("mission-result-#{rendered_body(mission.id)}", "li", %{}, [
        node(
          "mission-result-button-#{rendered_body(mission.id)}",
          "button",
          %{
            "type" => "button",
            "phx-click" => "set_context",
            "phx-value-scope-kind" => "mission",
            "phx-value-scope-id" => mission.id,
            "class" => "w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          },
          [
            mission.label,
            node(
              "mission-result-kind-#{rendered_body(mission.id)}",
              "span",
              %{"class" => "ml-2 font-mono text-xs text-base-content/60"},
              ["mission"]
            )
          ]
        )
      ])
    ]
  end

  defp spacecraft_result_nodes(spacecraft) do
    spacecraft
    |> Enum.with_index()
    |> Enum.map(fn {spacecraft, index} ->
      key = "spacecraft-result-#{rendered_body(spacecraft.spacecraft_id)}-#{index}"

      spacecraft_id_nodes =
        if truthy?(spacecraft.scid) do
          [
            node(
              "#{key}-scid",
              "span",
              %{"class" => "ml-2 font-mono text-xs text-base-content/60"},
              [spacecraft.scid]
            )
          ]
        else
          []
        end

      node(key, "li", %{}, [
        node(
          "#{key}-button",
          "button",
          %{
            "type" => "button",
            "phx-click" => "set_context",
            "phx-value-scope-kind" => "spacecraft",
            "phx-value-scope-id" => spacecraft.spacecraft_id,
            "phx-value-spacecraft-id" => spacecraft.spacecraft_id,
            "class" => "w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          },
          [spacecraft.display_name] ++ spacecraft_id_nodes
        )
      ])
    end)
  end

  defp contact_result_nodes(contacts) do
    contacts
    |> Enum.with_index()
    |> Enum.map(fn {contact, index} ->
      key = "contact-result-#{rendered_body(contact.id)}-#{index}"

      node(key, "li", %{}, [
        node(
          "#{key}-button",
          "button",
          %{
            "type" => "button",
            "phx-click" => "set_context",
            "phx-value-scope-kind" => "contact",
            "phx-value-scope-id" => contact.id,
            "data-dashboard-context-result" => "contact",
            "data-dashboard-context-contact-kind" => contact.kind,
            "data-dashboard-context-contact-id" => contact.id,
            "class" => "w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
          },
          [
            contact.label,
            node(
              "#{key}-kind",
              "span",
              %{"class" => "ml-2 font-mono text-xs text-base-content/60"},
              [contact.kind]
            )
          ]
        )
      ])
    end)
  end

  defp resource_result_nodes(results, key_prefix, scope_kind, kind_label, id_attribute) do
    results
    |> Enum.with_index()
    |> Enum.map(fn {result, index} ->
      key = "#{key_prefix}-result-#{rendered_body(result.id)}-#{index}"

      attrs =
        %{
          "type" => "button",
          "phx-click" => "set_context",
          "phx-value-scope-kind" => scope_kind,
          "phx-value-scope-id" => result.id,
          "data-dashboard-context-result" => scope_kind,
          "class" => "w-full rounded px-2 py-1 text-left text-sm hover:bg-base-300"
        }
        |> Map.put(id_attribute, result.id)

      node(key, "li", %{}, [
        node("#{key}-button", "button", attrs, [
          result.label,
          node(
            "#{key}-kind",
            "span",
            %{"class" => "ml-2 font-mono text-xs text-base-content/60"},
            [kind_label]
          )
        ])
      ])
    end)
  end

  defp no_matches_nodes(no_matches?) do
    if truthy?(no_matches?) do
      [
        node(
          "context-no-matches",
          "li",
          %{"class" => "px-2 py-1 text-sm text-base-content/60"},
          ["No context matches."]
        )
      ]
    else
      []
    end
  end

  defp node(key, tag, attrs, children) do
    %{
      key: key,
      tag: tag,
      attrs: raw_attributes(attrs),
      children: Enum.map(children, &rendered_child/1)
    }
  end

  defp rendered_child(%{tag: _tag} = node), do: node
  defp rendered_child(value), do: rendered_body(value)

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), rendered_body(value))
    end)
  end

  defp truthy?(value), do: value not in [nil, false]

  defp rendered_body(nil), do: ""
  defp rendered_body(value), do: to_string(value)
end
