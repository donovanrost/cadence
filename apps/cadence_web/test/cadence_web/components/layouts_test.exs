defmodule CadenceWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias CadenceWeb.Layouts

  test "renders controller flashes through the LiveToast host" do
    document =
      render_component(&Layouts.auth/1,
        flash: %{"error" => "The supplied credentials were rejected."},
        inner_content: "Sign-in page"
      )
      |> LazyHTML.from_fragment()

    host = LazyHTML.query(document, "#toast-group")
    toast = LazyHTML.query(host, "#flash-error[role='alert'][phx-hook='LiveToast']")

    assert ["error"] = LazyHTML.attribute(toast, "data-kind")
    assert LazyHTML.text(toast) =~ "The supplied credentials were rejected."
  end

  test "global sidebar projects the exact JSON-safe admin drawer through one non-SSR parent" do
    vue = render_global_sidebar(nav_context: :admin, nav_item: :admin_organizations)

    assert vue.component == "GlobalSidebarNavigation"
    assert vue.class == "drawer-side"
    refute vue.ssr

    presentation = vue.props["presentation"]
    assert presentation == Jason.decode!(Jason.encode!(presentation))

    assert presentation["overlay"] == %{
             "attrs" => %{"aria-label" => "close sidebar", "for" => "sidebar-drawer"},
             "class" => "drawer-overlay"
           }

    assert presentation["root"] == %{
             "attrs" => %{"data-sidebar-collapsible" => ""},
             "collapsed_class" =>
               "sidebar-collapsible sidebar-collapsed min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative",
             "expanded_class" =>
               "sidebar-collapsible sidebar-expanded min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative"
           }

    assert presentation["header"] == %{
             "class" => "px-3 h-10 flex items-center border-b border-primary/20",
             "link" => %{
               "attrs" => %{
                 "data-phx-link" => "redirect",
                 "data-phx-link-state" => "push",
                 "href" => "/"
               },
               "class" => "flex items-center gap-2",
               "icon_class" => "text-primary font-bold text-sm",
               "icon_text" => "◆",
               "label" => "CADENCE",
               "label_class" => "text-xs font-bold tracking-[0.15em] text-primary sidebar-label"
             }
           }

    navigation = presentation["navigation"]

    assert navigation["class"] == "flex-1 overflow-y-auto py-2"
    assert navigation["list_class"] == "menu menu-sm space-y-0.5"

    assert navigation["section"] == %{
             "class" => "px-3 mb-2 sidebar-expanded-only",
             "label" => "Administration",
             "label_class" => "hud-label"
           }

    assert navigation["items"] == [
             %{
               "active" => false,
               "attrs" => %{
                 "data-phx-link" => "redirect",
                 "data-phx-link-state" => "push",
                 "href" => "/admin"
               },
               "class" =>
                 "flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30",
               "icon_class" => "hero-chart-bar-square h-4 w-4 opacity-80 flex-shrink-0",
               "key" => "admin-dashboard",
               "label" => "Dashboard",
               "label_class" => "sidebar-label"
             },
             %{
               "active" => true,
               "attrs" => %{
                 "data-phx-link" => "redirect",
                 "data-phx-link-state" => "push",
                 "href" => "/admin/organizations"
               },
               "class" =>
                 "flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]",
               "icon_class" => "hero-building-office h-4 w-4 opacity-80 flex-shrink-0",
               "key" => "admin-organizations",
               "label" => "Organizations",
               "label_class" => "sidebar-label"
             },
             %{
               "active" => false,
               "attrs" => %{
                 "data-phx-link" => "redirect",
                 "data-phx-link-state" => "push",
                 "href" => "/admin/runtime"
               },
               "class" =>
                 "flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30",
               "icon_class" => "hero-signal h-4 w-4 opacity-80 flex-shrink-0",
               "key" => "admin-runtime",
               "label" => "Runtime",
               "label_class" => "sidebar-label"
             }
           ]

    sign_out = presentation["sign_out"]
    fields = Map.new(sign_out["form"]["hidden_fields"], &{&1["attrs"]["name"], &1["attrs"]})

    assert sign_out["class"] == "px-2 py-2 border-t border-primary/20"

    assert sign_out["form"]["attrs"] == %{
             "action" => "/session",
             "class" => "w-full",
             "method" => "post"
           }

    assert fields["_method"] == %{
             "name" => "_method",
             "type" => "hidden",
             "value" => "delete"
           }

    assert fields["_csrf_token"]["hidden"] == ""
    assert fields["_csrf_token"]["name"] == "_csrf_token"
    assert fields["_csrf_token"]["type"] == "hidden"
    assert is_binary(fields["_csrf_token"]["value"])
    assert fields["_csrf_token"]["value"] != ""

    assert sign_out["form"]["button"] == %{
             "attrs" => %{"type" => "submit"},
             "class" =>
               "btn btn-ghost btn-sm w-full justify-start gap-2 text-xs uppercase tracking-wide text-base-content/60",
             "icon_class" => "hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80",
             "label" => "Sign out",
             "label_class" => "sidebar-label"
           }

    assert presentation["collapse"] == %{
             "attrs" => %{"title" => "Toggle sidebar", "type" => "button"},
             "class" => "sidebar-toggle-btn hidden lg:flex",
             "icon_class" => "hero-chevron-left h-3 w-3 toggle-chevron transition-transform"
           }
  end

  test "global sidebar preserves organization visibility and branch fallbacks" do
    organization =
      Organization.new(%{
        organization_id: "organization-global-sidebar-test",
        display_name: "Cadence Ops",
        slug: "cadence-ops"
      })

    for capability <- [:organization_admin, :platform_admin] do
      scope = %Cadence.Auth.Scope{
        organization: organization,
        capabilities: MapSet.new([capability])
      }

      presentation =
        render_global_sidebar(
          current_scope: scope,
          nav_context: :organization,
          nav_item: :provider_accounts
        ).props["presentation"]

      assert presentation == Jason.decode!(Jason.encode!(presentation))
      assert presentation["navigation"]["section"]["label"] == "Cadence Ops"

      assert Enum.map(presentation["navigation"]["items"], fn item ->
               %{
                 "active" => item["active"],
                 "href" => item["attrs"]["href"],
                 "icon_class" => item["icon_class"],
                 "id" => item["attrs"]["id"],
                 "label" => item["label"]
               }
             end) == [
               %{
                 "active" => false,
                 "href" => "/",
                 "icon_class" => "hero-home h-4 w-4 opacity-80 flex-shrink-0",
                 "id" => nil,
                 "label" => "Home"
               },
               %{
                 "active" => false,
                 "href" => "/missions",
                 "icon_class" => "hero-rocket-launch h-4 w-4 opacity-80 flex-shrink-0",
                 "id" => nil,
                 "label" => "Missions"
               },
               %{
                 "active" => true,
                 "href" => "/provider-accounts",
                 "icon_class" => "hero-globe-alt h-4 w-4 opacity-80 flex-shrink-0",
                 "id" => "provider-accounts-nav-link",
                 "label" => "Provider Accounts"
               }
             ]

      assert Enum.all?(presentation["navigation"]["items"], fn item ->
               item["attrs"]["data-phx-link"] == "redirect" and
                 item["attrs"]["data-phx-link-state"] == "push"
             end)
    end

    member_scope = %Cadence.Auth.Scope{organization: organization}

    member_navigation =
      render_global_sidebar(
        current_scope: member_scope,
        nav_context: :organization,
        nav_item: :organization_home
      ).props["presentation"]["navigation"]

    assert Enum.map(member_navigation["items"], & &1["label"]) == ["Home", "Missions"]
    assert hd(member_navigation["items"])["active"]
    assert hd(member_navigation["items"])["class"] =~ "border-primary"

    organization_fallback =
      render_global_sidebar(nav_context: :organization).props["presentation"]["navigation"]

    assert organization_fallback["section"]["label"] == "Organization"
    assert Enum.map(organization_fallback["items"], & &1["label"]) == ["Home", "Missions"]

    branch_fallback = render_global_sidebar().props["presentation"]["navigation"]
    assert branch_fallback["section"] == nil
    assert branch_fallback["items"] == []
  end

  test "mission sidebar projects the exact JSON-safe drawer presentation through one non-SSR parent" do
    organization =
      Organization.new(%{
        organization_id: "organization-layout-test",
        display_name: "Cadence Ops",
        slug: "cadence-ops"
      })

    mission =
      Mission.new(%{
        mission_id: "mission-layout-test",
        organization_id: organization.organization_id,
        display_name: "Alpha Mission",
        slug: "alpha"
      })

    vue =
      render_mission_sidebar(
        current_scope: %Cadence.Auth.Scope{organization: organization},
        current_mission: mission,
        nav_item: :comms_routing
      )

    assert vue.component == "MissionSidebarNavigation"
    assert vue.class == "drawer-side"
    refute vue.ssr

    presentation = vue.props["presentation"]
    assert presentation == Jason.decode!(Jason.encode!(presentation))

    assert presentation["overlay"] == %{
             "attrs" => %{"aria-label" => "close sidebar", "for" => "sidebar-drawer"},
             "class" => "drawer-overlay"
           }

    assert presentation["root"] == %{
             "attrs" => %{"data-sidebar-collapsible" => ""},
             "collapsed_class" =>
               "sidebar-collapsible sidebar-collapsed min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative",
             "expanded_class" =>
               "sidebar-collapsible sidebar-expanded min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative"
           }

    assert presentation["organization"]["link"] == %{
             "attrs" => %{
               "data-phx-link" => "redirect",
               "data-phx-link-state" => "push",
               "href" => "/"
             },
             "class" =>
               "flex items-center gap-2 text-xs text-base-content/60 hover:text-base-content",
             "icon_class" => "hero-chevron-left h-3 w-3",
             "label" => "Cadence Ops",
             "label_class" => "sidebar-label tracking-wide uppercase"
           }

    assert presentation["mission"] == %{
             "class" => "px-3 pt-4 pb-2 sidebar-expanded-only",
             "display_name" => "Alpha Mission",
             "name_class" => "text-sm font-bold text-base-content truncate",
             "slug" => "alpha",
             "slug_class" => "text-xs text-base-content/50 font-mono truncate",
             "slug_visible" => true
           }

    items = presentation["navigation"]["items"]

    assert Enum.map(items, & &1["label"]) == [
             "Overview",
             "Spacecraft",
             "Applications",
             "Catalog",
             "Ops",
             "Comms"
           ]

    links =
      Enum.flat_map(items, fn
        %{"kind" => "link"} = item -> [item]
        %{"kind" => "section", "children" => children} -> children
      end)

    assert Enum.map(links, & &1["attrs"]["href"]) == [
             "/missions/mission-layout-test",
             "/missions/mission-layout-test/spacecraft",
             "/missions/mission-layout-test/applications",
             "/missions/mission-layout-test/catalog",
             "/missions/mission-layout-test/ops/dashboards",
             "/missions/mission-layout-test/comms",
             "/missions/mission-layout-test/comms/transports",
             "/missions/mission-layout-test/comms/ground-stations",
             "/missions/mission-layout-test/comms/routing",
             "/missions/mission-layout-test/comms/validation"
           ]

    assert Enum.all?(links, fn link ->
             link["attrs"]["data-phx-link"] == "redirect" and
               link["attrs"]["data-phx-link-state"] == "push"
           end)

    ops = Enum.find(items, &(&1["key"] == "ops"))
    comms = Enum.find(items, &(&1["key"] == "comms"))
    routing = Enum.find(comms["children"], &(&1["key"] == "comms-routing"))

    refute ops["active"]
    refute ops["expanded"]

    assert ops["summary_class"] ==
             "list-none cursor-pointer flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30"

    assert comms["active"]
    assert comms["expanded"]

    assert comms["summary_class"] ==
             "list-none cursor-pointer flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]"

    assert routing["active"]
    assert routing["class"] =~ "text-primary"
    assert routing["icon_class"] =~ "bg-primary"

    sign_out = presentation["sign_out"]
    fields = Map.new(sign_out["form"]["hidden_fields"], &{&1["attrs"]["name"], &1["attrs"]})

    assert sign_out["form"]["attrs"] == %{
             "action" => "/session",
             "class" => "w-full",
             "method" => "post"
           }

    assert fields["_method"] == %{
             "name" => "_method",
             "type" => "hidden",
             "value" => "delete"
           }

    assert fields["_csrf_token"]["hidden"] == ""
    assert fields["_csrf_token"]["type"] == "hidden"
    assert is_binary(fields["_csrf_token"]["value"])
    assert fields["_csrf_token"]["value"] != ""
    assert sign_out["form"]["button"]["attrs"] == %{"type" => "submit"}
    assert sign_out["form"]["button"]["label"] == "Sign out"

    assert presentation["collapse"] == %{
             "attrs" => %{"title" => "Toggle sidebar", "type" => "button"},
             "class" => "sidebar-toggle-btn hidden lg:flex",
             "icon_class" => "hero-chevron-left h-3 w-3 toggle-chevron transition-transform"
           }
  end

  test "mission sidebar preserves Ops expansion and missing-scope fallbacks" do
    mission =
      Mission.new(%{
        mission_id: "mission-ops-layout-test",
        organization_id: "organization-layout-test",
        display_name: "Ops Mission",
        slug: "ops"
      })

    ops_presentation =
      render_mission_sidebar(current_mission: mission, nav_item: :ops_dashboards).props[
        "presentation"
      ]

    ops = Enum.find(ops_presentation["navigation"]["items"], &(&1["key"] == "ops"))
    dashboards = hd(ops["children"])

    assert ops["active"]
    assert ops["expanded"]
    assert dashboards["active"]

    for {nav_item, key} <- [
          mission_overview: "overview",
          spacecraft: "spacecraft",
          mission_applications: "applications",
          catalog: "catalog"
        ] do
      presentation =
        render_mission_sidebar(current_mission: mission, nav_item: nav_item).props["presentation"]

      active_item =
        Enum.find(presentation["navigation"]["items"], &(&1["key"] == key))

      assert active_item["active"]
      assert active_item["class"] =~ "bg-primary/10"
      assert active_item["class"] =~ "border-primary"
    end

    provider_presentation =
      render_mission_sidebar(current_mission: mission, nav_item: :comms_providers).props[
        "presentation"
      ]

    comms =
      Enum.find(provider_presentation["navigation"]["items"], &(&1["key"] == "comms"))

    assert comms["active"]
    assert comms["expanded"]
    refute Enum.any?(comms["children"], &(&1["label"] == "Providers"))

    fallback = render_mission_sidebar().props["presentation"]

    assert fallback["organization"]["link"]["label"] == "Organization"
    assert fallback["mission"]["display_name"] == "Mission"
    refute fallback["mission"]["slug_visible"]
    assert fallback["navigation"]["items"] == []
  end

  defp render_mission_sidebar(assigns \\ []) do
    [
      flash: %{},
      inner_content: "Mission content",
      current_scope: nil,
      current_mission: nil,
      nav_item: nil
    ]
    |> Keyword.merge(assigns)
    |> then(fn merged_assigns ->
      render_component(&Layouts.mission_sidebar/1, merged_assigns)
    end)
    |> LiveVue.Test.get_vue(id: "mission-sidebar-navigation")
  end

  defp render_global_sidebar(assigns \\ []) do
    [
      flash: %{},
      inner_content: "Global content",
      current_scope: nil,
      nav_context: nil,
      nav_item: nil
    ]
    |> Keyword.merge(assigns)
    |> then(fn merged_assigns -> render_component(&Layouts.sidebar/1, merged_assigns) end)
    |> LiveVue.Test.get_vue(id: "global-sidebar-navigation")
  end
end
