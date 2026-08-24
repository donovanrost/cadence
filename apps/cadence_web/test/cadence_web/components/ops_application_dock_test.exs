defmodule CadenceWeb.Components.OpsApplicationDockTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Cadence.Applications.{ApplicationInstallation, OpsDockSurface, SurfaceDefinition}
  alias CadenceWeb.Components.OpsApplicationDock

  test "emits one non-SSR LiveVue host with the exact dock chrome presentation" do
    surface = surface(id: "installation-1:surface-1")

    html =
      render_component(&OpsApplicationDock.ops_application_dock/1,
        surfaces: [surface]
      )

    vue = LiveVue.Test.get_vue(html, id: "ops-application-dock-component")
    presentation = vue.props["presentation"]

    assert vue.component == "OpsApplicationDock"
    assert vue.id == "ops-application-dock-component"
    assert vue.ssr == false
    assert vue.class == "contents"
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert Map.keys(vue.props) == ["presentation"]

    assert presentation["root"] == %{
             "attrs" => %{"id" => "ops-application-dock", "open" => ""},
             "class" => "group shrink-0 border-t border-primary/25 bg-base-200/80"
           }

    assert presentation["summary"] == %{
             "class" =>
               "flex h-8 cursor-pointer list-none items-center border-b border-base-300/70 px-3 marker:hidden"
           }

    assert presentation["label"] == %{
             "class" => "hud-label mr-4",
             "text" => "Operations dock"
           }

    assert presentation["navigation"]["attrs"] == %{
             "aria-label" => "Application dock surfaces"
           }

    assert presentation["navigation"]["class"] ==
             "flex min-w-0 flex-1 items-stretch gap-1 self-stretch"

    assert presentation["chevron"] == %{
             "class" =>
               "hero-chevron-down size-4 text-base-content/45 transition-transform group-open:rotate-180"
           }

    assert presentation["panel"] == %{
             "attrs" => %{"id" => "ops-dock-surface-host", "role" => "tabpanel"},
             "class" => "h-40 overflow-hidden bg-base-100",
             "message" => %{
               "class" => "flex h-full items-center justify-center text-sm text-base-content/45",
               "text" => "The application surface is registered with the Ops host."
             }
           }
  end

  test "presentation preserves input order, first-tab selection, unusual ids, and JSON totality" do
    surfaces = [
      surface(
        id: "install alpha:surface/one.two",
        application_key: "application-alpha",
        surface_id: "surface.one",
        label: "Alpha <Ops>",
        order: 99
      ),
      surface(
        id: "install-beta:surface::two",
        application_key: "",
        surface_id: "",
        label: "",
        order: -10
      )
    ]

    presentation = OpsApplicationDock.presentation(surfaces)
    [first, second] = presentation["navigation"]["tabs"]

    assert presentation == Jason.decode!(Jason.encode!(presentation))

    assert Enum.map(presentation["navigation"]["tabs"], & &1["key"]) ==
             Enum.map(surfaces, & &1.id)

    assert Enum.map(presentation["navigation"]["tabs"], & &1["label"]) == ["Alpha <Ops>", ""]

    assert first == %{
             "attrs" => %{
               "aria-selected" => "true",
               "data-application-key" => "application-alpha",
               "data-surface-id" => "surface.one",
               "id" => "ops-dock-tab-install-alpha-surface-one-two",
               "role" => "tab",
               "type" => "button"
             },
             "class" =>
               "relative px-3 font-mono text-[0.68rem] font-semibold uppercase tracking-[0.1em] text-primary after:absolute after:inset-x-2 after:bottom-0 after:h-px after:bg-primary",
             "key" => "install alpha:surface/one.two",
             "label" => "Alpha <Ops>"
           }

    assert second == %{
             "attrs" => %{
               "aria-selected" => "false",
               "data-application-key" => "",
               "data-surface-id" => "",
               "id" => "ops-dock-tab-install-beta-surface--two",
               "role" => "tab",
               "type" => "button"
             },
             "class" =>
               "relative px-3 font-mono text-[0.68rem] font-semibold uppercase tracking-[0.1em] text-base-content/50",
             "key" => "install-beta:surface::two",
             "label" => ""
           }
  end

  defp surface(opts) do
    id = Keyword.fetch!(opts, :id)
    application_key = Keyword.get(opts, :application_key, "application-one")
    surface_id = Keyword.get(opts, :surface_id, "surface-one")

    installation = %ApplicationInstallation{
      application_installation_id: "installation-one",
      organization_id: "organization-one",
      mission_id: "mission-one",
      scope_kind: :mission,
      scope_id: "mission-one",
      application_key: application_key,
      application_version: 1,
      lifecycle_state: :installed
    }

    surface_definition = %SurfaceDefinition{
      surface_id: surface_id,
      version: 1,
      purpose: :operations,
      scope: :mission,
      placement: :ops_dock,
      data_contract: %{query_id: "query-one", version: 1},
      renderer: {:declarative, "renderer-one"}
    }

    %OpsDockSurface{
      id: id,
      application_key: application_key,
      application_name: "Application One",
      application_installation: installation,
      surface_definition: surface_definition,
      label: Keyword.get(opts, :label, "Application One"),
      order: Keyword.get(opts, :order, 0)
    }
  end
end
