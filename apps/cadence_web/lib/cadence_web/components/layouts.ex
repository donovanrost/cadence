defmodule CadenceWeb.Layouts do
  @moduledoc false

  use CadenceWeb, :html

  import CadenceWeb.Components.OpsShell
  import CadenceWeb.Components.OpsApplicationDock
  import CadenceWeb.Components.Sidebar

  embed_templates("layouts/*")

  @nav_item_base_class "flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all"
  @nav_item_active_class "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]"
  @nav_item_inactive_class "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30"
  @nav_section_summary_prefix "list-none cursor-pointer"
  @nav_child_base_class "flex items-center gap-2 px-3 py-1.5 text-xs tracking-wide uppercase border-l-2 border-transparent transition-all"

  defp auth_layout_brand_presentation do
    %{
      "link" => %{
        "attrs" => raw_attrs(%{"href" => ~p"/"}),
        "class" => "inline-block font-mono text-sm tracking-[0.28em] uppercase text-primary",
        "label" => "Cadence"
      },
      "tagline" => %{
        "class" => "mt-1 text-xs text-base-content/50",
        "text" => "Ground data control plane"
      }
    }
  end

  defp global_sidebar_navigation_presentation(assigns) do
    %{
      "overlay" => %{
        "class" => "drawer-overlay",
        "attrs" => raw_attrs(%{"aria-label" => "close sidebar", "for" => "sidebar-drawer"})
      },
      "root" => %{
        "attrs" => raw_attrs(%{"data-sidebar-collapsible" => true}),
        "expanded_class" =>
          "sidebar-collapsible sidebar-expanded min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative",
        "collapsed_class" =>
          "sidebar-collapsible sidebar-collapsed min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative"
      },
      "header" => %{
        "class" => "px-3 h-10 flex items-center border-b border-primary/20",
        "link" => %{
          "attrs" => global_navigate_attrs(~p"/"),
          "class" => "flex items-center gap-2",
          "icon_class" => "text-primary font-bold text-sm",
          "icon_text" => "◆",
          "label_class" => "text-xs font-bold tracking-[0.15em] text-primary sidebar-label",
          "label" => "CADENCE"
        }
      },
      "navigation" =>
        global_navigation_presentation(
          assigns[:nav_context],
          assigns[:current_scope],
          assigns[:nav_item]
        ),
      "sign_out" => sign_out_presentation(),
      "collapse" => %{
        "class" => "sidebar-toggle-btn hidden lg:flex",
        "attrs" => raw_attrs(%{"title" => "Toggle sidebar", "type" => "button"}),
        "icon_class" => "hero-chevron-left h-3 w-3 toggle-chevron transition-transform"
      }
    }
  end

  defp global_navigation_presentation(:admin, _scope, nav_item) do
    global_navigation_presentation(
      %{
        "class" => "px-3 mb-2 sidebar-expanded-only",
        "label_class" => "hud-label",
        "label" => "Administration"
      },
      [
        global_nav_link(
          "admin-dashboard",
          "Dashboard",
          ~p"/admin",
          "hero-chart-bar-square",
          nav_item == :admin_dashboard
        ),
        global_nav_link(
          "admin-organizations",
          "Organizations",
          ~p"/admin/organizations",
          "hero-building-office",
          nav_item == :admin_organizations
        ),
        global_nav_link(
          "admin-runtime",
          "Runtime",
          ~p"/admin/runtime",
          "hero-signal",
          nav_item == :admin_runtime
        )
      ]
    )
  end

  defp global_navigation_presentation(:organization, scope, nav_item) do
    items = [
      global_nav_link(
        "organization-home",
        "Home",
        ~p"/",
        "hero-home",
        nav_item == :organization_home
      ),
      global_nav_link(
        "missions",
        "Missions",
        ~p"/missions",
        "hero-rocket-launch",
        nav_item == :missions
      )
    ]

    items =
      if provider_accounts_visible?(scope) do
        items ++
          [
            global_nav_link(
              "provider-accounts",
              "Provider Accounts",
              ~p"/provider-accounts",
              "hero-globe-alt",
              nav_item == :provider_accounts,
              "provider-accounts-nav-link"
            )
          ]
      else
        items
      end

    global_navigation_presentation(
      %{
        "class" => "px-3 mb-2 sidebar-expanded-only",
        "label_class" => "hud-label",
        "label" => organization_name(scope)
      },
      items
    )
  end

  defp global_navigation_presentation(_nav_context, _scope, _nav_item),
    do: global_navigation_presentation(nil, [])

  defp global_navigation_presentation(section, items) do
    %{
      "class" => "flex-1 overflow-y-auto py-2",
      "section" => section,
      "list_class" => "menu menu-sm space-y-0.5",
      "items" => items
    }
  end

  defp global_nav_link(key, label, href, icon, active?, id \\ nil) do
    %{
      "key" => key,
      "attrs" => global_navigate_attrs(href, %{"id" => id}),
      "class" => nav_item_class(active?),
      "icon_class" => "#{icon} h-4 w-4 opacity-80 flex-shrink-0",
      "label_class" => "sidebar-label",
      "label" => label,
      "active" => active?
    }
  end

  defp global_navigate_attrs(href, extra_attrs \\ %{}) do
    %{
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push",
      "href" => href
    }
    |> Map.merge(extra_attrs)
    |> raw_attrs()
  end

  defp mission_sidebar_navigation_presentation(assigns) do
    mission = assigns[:current_mission]
    nav_item = assigns[:nav_item]

    %{
      "overlay" => %{
        "class" => "drawer-overlay",
        "attrs" => %{"aria-label" => "close sidebar", "for" => "sidebar-drawer"}
      },
      "root" => %{
        "attrs" => %{"data-sidebar-collapsible" => ""},
        "expanded_class" =>
          "sidebar-collapsible sidebar-expanded min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative",
        "collapsed_class" =>
          "sidebar-collapsible sidebar-collapsed min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative"
      },
      "organization" => organization_presentation(assigns[:current_scope]),
      "mission" => mission_presentation(mission),
      "navigation" => %{
        "class" => "flex-1 overflow-y-auto py-2",
        "list_class" => "menu menu-sm space-y-0.5",
        "items" => navigation_items(mission, nav_item)
      },
      "sign_out" => sign_out_presentation(),
      "collapse" => %{
        "class" => "sidebar-toggle-btn hidden lg:flex",
        "attrs" => %{"title" => "Toggle sidebar", "type" => "button"},
        "icon_class" => "hero-chevron-left h-3 w-3 toggle-chevron transition-transform"
      }
    }
  end

  defp organization_presentation(scope) do
    %{
      "class" => "px-3 h-10 flex items-center border-b border-primary/20",
      "link" => %{
        "attrs" => navigate_attrs(~p"/"),
        "class" => "flex items-center gap-2 text-xs text-base-content/60 hover:text-base-content",
        "icon_class" => "hero-chevron-left h-3 w-3",
        "label_class" => "sidebar-label tracking-wide uppercase",
        "label" => organization_name(scope)
      }
    }
  end

  defp organization_name(%{organization: %{display_name: display_name}}), do: display_name
  defp organization_name(_scope), do: "Organization"

  defp mission_presentation(nil) do
    %{
      "class" => "px-3 pt-4 pb-2 sidebar-expanded-only",
      "name_class" => "text-sm font-bold text-base-content truncate",
      "display_name" => "Mission",
      "slug_class" => "text-xs text-base-content/50 font-mono truncate",
      "slug" => nil,
      "slug_visible" => false
    }
  end

  defp mission_presentation(mission) do
    %{
      "class" => "px-3 pt-4 pb-2 sidebar-expanded-only",
      "name_class" => "text-sm font-bold text-base-content truncate",
      "display_name" => mission.display_name,
      "slug_class" => "text-xs text-base-content/50 font-mono truncate",
      "slug" => mission.slug,
      "slug_visible" => true
    }
  end

  defp navigation_items(nil, _nav_item), do: []

  defp navigation_items(mission, nav_item) do
    mission_root = ~p"/missions/#{mission.mission_id}"

    [
      nav_link(
        "overview",
        "Overview",
        mission_root,
        "hero-chart-bar-square",
        nav_item == :mission_overview
      ),
      nav_link(
        "spacecraft",
        "Spacecraft",
        ~p"/missions/#{mission.mission_id}/spacecraft",
        "hero-rocket-launch",
        nav_item == :spacecraft
      ),
      nav_link(
        "applications",
        "Applications",
        ~p"/missions/#{mission.mission_id}/applications",
        "hero-squares-2x2",
        nav_item == :mission_applications
      ),
      nav_link(
        "catalog",
        "Catalog",
        ~p"/missions/#{mission.mission_id}/catalog",
        "hero-circle-stack",
        nav_item == :catalog
      ),
      nav_section(
        "ops",
        "Ops",
        "hero-presentation-chart-line",
        section_active?(nav_item, :ops),
        [
          nav_child(
            "dashboards",
            "Dashboards",
            ~p"/missions/#{mission.mission_id}/ops/dashboards",
            nav_item == :ops_dashboards
          )
        ]
      ),
      nav_section(
        "comms",
        "Comms",
        "hero-signal",
        section_active?(nav_item, :comms),
        [
          nav_child(
            "comms-overview",
            "Overview",
            ~p"/missions/#{mission.mission_id}/comms",
            nav_item == :comms_overview
          ),
          nav_child(
            "comms-transports",
            "Transports",
            ~p"/missions/#{mission.mission_id}/comms/transports",
            nav_item == :comms_transports
          ),
          nav_child(
            "comms-ground-stations",
            "Ground Stations",
            ~p"/missions/#{mission.mission_id}/comms/ground-stations",
            nav_item == :comms_ground_stations
          ),
          nav_child(
            "comms-routing",
            "Routing",
            ~p"/missions/#{mission.mission_id}/comms/routing",
            nav_item == :comms_routing
          ),
          nav_child(
            "comms-validation",
            "Validation",
            ~p"/missions/#{mission.mission_id}/comms/validation",
            nav_item == :comms_validation
          )
        ]
      )
    ]
  end

  defp nav_link(key, label, href, icon, active?) do
    %{
      "kind" => "link",
      "key" => key,
      "attrs" => navigate_attrs(href),
      "class" => nav_item_class(active?),
      "icon_class" => "#{icon} h-4 w-4 opacity-80 flex-shrink-0",
      "label_class" => "sidebar-label",
      "label" => label,
      "active" => active?
    }
  end

  defp nav_section(key, label, icon, active?, children) do
    %{
      "kind" => "section",
      "key" => key,
      "details_class" => "group",
      "expanded" => active?,
      "summary_class" => nav_section_summary_class(active?),
      "icon_class" => "#{icon} h-4 w-4 opacity-80 flex-shrink-0",
      "label_class" => "sidebar-label flex-1",
      "label" => label,
      "chevron_class" =>
        "hero-chevron-right h-3 w-3 opacity-60 transition-transform group-data-[state=open]:rotate-90 sidebar-label",
      "list_class" => "mt-0.5 space-y-0.5",
      "children" => children,
      "active" => active?
    }
  end

  defp nav_child(key, label, href, active?) do
    %{
      "key" => key,
      "attrs" => navigate_attrs(href),
      "class" => nav_child_class(active?),
      "icon_container_class" => "h-4 w-4 flex items-center justify-center flex-shrink-0",
      "icon_class" =>
        "h-1.5 w-1.5 rounded-full transition-colors #{if(active?, do: "bg-primary", else: "bg-base-content/30")}",
      "label_class" => "sidebar-label",
      "label" => label,
      "active" => active?
    }
  end

  defp nav_item_class(true), do: "#{@nav_item_base_class} #{@nav_item_active_class}"
  defp nav_item_class(false), do: "#{@nav_item_base_class} #{@nav_item_inactive_class}"

  defp nav_section_summary_class(active?),
    do: "#{@nav_section_summary_prefix} #{nav_item_class(active?)}"

  defp nav_child_class(true), do: "#{@nav_child_base_class} text-primary"

  defp nav_child_class(false),
    do: "#{@nav_child_base_class} text-base-content/60 hover:text-base-content"

  defp sign_out_presentation do
    %{
      "class" => "px-2 py-2 border-t border-primary/20",
      "form" => %{
        "attrs" => %{"action" => ~p"/session", "class" => "w-full", "method" => "post"},
        "hidden_fields" => [
          %{
            "key" => "method",
            "attrs" => %{"name" => "_method", "type" => "hidden", "value" => "delete"}
          },
          %{
            "key" => "csrf",
            "attrs" => %{
              "hidden" => "",
              "name" => "_csrf_token",
              "type" => "hidden",
              "value" => Plug.CSRFProtection.get_csrf_token_for(~p"/session")
            }
          }
        ],
        "button" => %{
          "attrs" => %{"type" => "submit"},
          "class" =>
            "btn btn-ghost btn-sm w-full justify-start gap-2 text-xs uppercase tracking-wide text-base-content/60",
          "icon_class" => "hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80",
          "label_class" => "sidebar-label",
          "label" => "Sign out"
        }
      }
    }
  end

  defp navigate_attrs(href) do
    %{
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push",
      "href" => href
    }
  end

  defp raw_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp provider_accounts_visible?(%{capabilities: capabilities}) do
    MapSet.member?(capabilities, :organization_admin) or
      MapSet.member?(capabilities, :platform_admin)
  end

  defp provider_accounts_visible?(_scope), do: false
end
