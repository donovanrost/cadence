defmodule CadenceWeb.CommsRoutingListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.{RoutingRuleStore, TransportStore}

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    routing_rules =
      RoutingRuleStore.list_routing_rules(scope.organization_id, mission.mission_id)

    spacecraft_by_id = spacecraft_lookup(scope.organization_id, mission.mission_id)
    transport_by_id = transport_lookup(scope.organization_id, mission.mission_id)

    routing_rule_rows =
      Enum.map(
        routing_rules,
        &routing_rule_row(&1, mission.mission_id, spacecraft_by_id, transport_by_id)
      )

    routing_rule_count = length(routing_rules)
    routing_rules_empty? = routing_rules == []

    {:ok,
     socket
     |> assign(:page_title, "Comms Routing")
     |> assign(:nav_item, :comms_routing)
     |> assign(:routing_rule_count, routing_rule_count)
     |> assign(:routing_rules_empty?, routing_rules_empty?)
     |> assign(:routing_rule_rows, routing_rule_rows)
     |> assign(
       :presentation,
       routing_list_presentation(
         mission,
         routing_rule_count,
         routing_rules_empty?,
         routing_rule_rows
       )
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-routing-list-page-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id="routing"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id}}
          v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  @doc false
  def presentation_attrs(attrs) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp routing_list_presentation(mission, routing_rule_count, routing_rules_empty?, rows) do
    new_rule_path = ~p"/missions/#{mission.mission_id}/comms/routing/new"

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "comms-routing-page",
            "class" => "space-y-6"
          })
      },
      "header" => header_presentation(mission, routing_rule_count, new_rule_path),
      "empty_state" => empty_state_presentation(routing_rules_empty?, new_rule_path),
      "card" => card_presentation(routing_rules_empty?, rows)
    }
  end

  defp header_presentation(mission, routing_rule_count, new_rule_path) do
    %{
      "attrs" => presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
      "body" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-end justify-between gap-4"})
      },
      "content" => %{"attrs" => %{}},
      "breadcrumbs" => breadcrumbs_presentation(mission),
      "title" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
          }),
        "text" => "Routing",
        "suffix" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "ml-3 font-mono text-base text-base-content/60"
            }),
          "text" => "#{routing_rule_count} rules"
        }
      },
      "subtitle" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
          }),
        "text" =>
          "Durable rules describing how spacecraft use transports for a purpose and direction."
      },
      "actions" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-center gap-2"}),
        "new_rule" => %{
          "attrs" =>
            navigate_attrs(new_rule_path, %{
              "id" => "new-routing-rule-link",
              "class" => "btn btn-primary btn-sm gap-1"
            }),
          "icon" => %{
            "attrs" => presentation_attrs(%{"class" => "hero-plus h-4 w-4"})
          },
          "text" => "New Routing Rule"
        }
      }
    }
  end

  defp breadcrumbs_presentation(mission) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "aria-label" => "Breadcrumb",
          "class" =>
            "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
        }),
      "items" => [
        %{
          "key" => "mission",
          "separator" => nil,
          "link" => %{
            "attrs" =>
              navigate_attrs(~p"/missions/#{mission.mission_id}", %{
                "class" => "hover:text-primary transition-colors"
              }),
            "text" => mission.display_name
          },
          "current" => nil
        },
        %{
          "key" => "comms",
          "separator" => breadcrumb_separator(),
          "link" => %{
            "attrs" =>
              navigate_attrs(~p"/missions/#{mission.mission_id}/comms", %{
                "class" => "hover:text-primary transition-colors"
              }),
            "text" => "Comms"
          },
          "current" => nil
        },
        %{
          "key" => "routing",
          "separator" => breadcrumb_separator(),
          "link" => nil,
          "current" => %{
            "attrs" => presentation_attrs(%{"class" => "text-primary/90"}),
            "text" => "Routing"
          }
        }
      ]
    }
  end

  defp breadcrumb_separator do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" => "text-base-content/20",
          "aria-hidden" => "true"
        }),
      "text" => "/"
    }
  end

  defp empty_state_presentation(true, new_rule_path) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" =>
            "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
        }),
      "title" => %{
        "attrs" => presentation_attrs(%{"class" => "hud-label"}),
        "text" => "No routing rules"
      },
      "description" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
          }),
        "text" =>
          "Create a routing rule to declare how a spacecraft should use an available transport."
      },
      "action_container" => %{
        "attrs" => presentation_attrs(%{"class" => "mt-5"})
      },
      "action" => %{
        "attrs" => navigate_attrs(new_rule_path, %{"class" => "btn btn-primary btn-sm"}),
        "icon" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"
            })
        },
        "text" => "Create the first routing rule"
      }
    }
  end

  defp empty_state_presentation(false, _new_rule_path), do: nil

  defp card_presentation(true, _rows), do: nil

  defp card_presentation(false, rows) do
    %{
      "attrs" => presentation_attrs(%{"class" => "card bg-base-200 border border-base-300"}),
      "body" => %{
        "attrs" => presentation_attrs(%{"class" => "card-body p-0"})
      },
      "list_component" => %{
        "attrs" => presentation_attrs(%{"id" => "routing-rules-list-component"})
      },
      "rows" => rows
    }
  end

  defp navigate_attrs(href, extra_attrs) do
    %{
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push",
      "href" => href
    }
    |> Map.merge(extra_attrs)
    |> presentation_attrs()
  end

  defp spacecraft_lookup(organization_id, mission_id) do
    organization_id
    |> Cadence.SpacecraftStore.list_spacecraft(mission_id)
    |> Map.new(&{&1.spacecraft_id, &1})
  end

  defp transport_lookup(organization_id, mission_id) do
    organization_id
    |> TransportStore.list_transports(mission_id)
    |> Map.new(&{&1.transport_id, &1})
  end

  defp routing_rule_row(rule, mission_id, spacecraft_by_id, transport_by_id) do
    %{
      id: "routing-rule-#{rule.routing_rule_id}",
      display_name: rule.display_name,
      spacecraft_name: spacecraft_name(spacecraft_by_id, rule.spacecraft_id),
      purpose_label: rule.purpose_label,
      direction: human_atom(rule.direction),
      transport_name: transport_name(transport_by_id, rule.transport_id),
      role: human_atom(rule.role),
      href: ~p"/missions/#{mission_id}/comms/routing/#{rule.routing_rule_id}"
    }
  end

  defp spacecraft_name(spacecraft_by_id, spacecraft_id) do
    case Map.fetch(spacecraft_by_id, spacecraft_id) do
      {:ok, spacecraft} -> spacecraft.display_name
      :error -> spacecraft_id
    end
  end

  defp transport_name(transport_by_id, transport_id) do
    case Map.fetch(transport_by_id, transport_id) do
      {:ok, transport} -> transport.display_name
      :error -> transport_id
    end
  end

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()
  end
end
