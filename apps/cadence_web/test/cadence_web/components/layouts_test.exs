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
end
