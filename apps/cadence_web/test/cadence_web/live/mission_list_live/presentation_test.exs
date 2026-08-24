defmodule CadenceWeb.MissionListLive.PresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.MissionListLive.Presentation

  test "empty presentation preserves the complete Mission List DOM and navigation contract" do
    presentation = Presentation.build([])

    assert presentation == %{
             root_class: "space-y-6",
             header: %{
               class: "border-b border-primary/20 pb-4",
               content_class: "flex items-end justify-between gap-4",
               eyebrow: %{class: "hud-label", text: "Organization"},
               title: %{
                 class: "mt-2 text-2xl font-bold text-base-content tracking-tight",
                 text: "Missions",
                 suffix: %{
                   class: "ml-3 font-mono text-base text-base-content/60",
                   text: "0 configured"
                 }
               },
               actions_class: "flex items-center gap-2",
               action: %{
                 attrs: %{
                   "data-phx-link" => "redirect",
                   "data-phx-link-state" => "push",
                   "href" => "/missions/new"
                 },
                 class: "btn btn-primary btn-sm gap-1",
                 icon_class: "hero-plus h-4 w-4",
                 label: "New Mission"
               }
             },
             empty_state: %{
               visible: true,
               id: "mission-list-empty-state",
               class:
                 "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
               icon_class: "hero-rocket-launch mx-auto h-10 w-10 text-base-content/30 block",
               title: %{class: "hud-label mt-3", text: "No missions yet"},
               description: %{
                 class: "mt-2 max-w-md mx-auto text-sm text-base-content/70",
                 text: "Create your first mission to get started."
               },
               action_container_class: "mt-5",
               action: %{
                 attrs: %{
                   "data-phx-link" => "redirect",
                   "data-phx-link-state" => "push",
                   "href" => "/missions/new"
                 },
                 class: "btn btn-primary btn-sm",
                 icon_class: "hero-plus -ml-0.5 mr-1 h-4 w-4",
                 label: "New Mission"
               }
             },
             card: %{
               visible: false,
               class: "card bg-base-200 border border-base-300",
               body_class: "card-body p-0",
               rows: []
             }
           }

    encoded = Jason.encode!(presentation)

    assert is_binary(encoded)
    assert Jason.decode!(encoded)["empty_state"]["visible"]
  end

  test "non-empty presentation preserves configured count and every existing row DTO field" do
    presentation =
      Presentation.build([
        mission_row("mission-alpha", "Alpha Mission", "alpha", 0, :info, "No spacecraft"),
        mission_row("mission-beta", "Beta Mission", "beta", 2, :ready, "Ready"),
        mission_row("mission-gamma", "Gamma Mission", "gamma", 1, :attention, "Needs setup")
      ])

    refute presentation.empty_state.visible
    assert presentation.card.visible
    assert presentation.header.title.suffix.text == "3 configured"

    assert presentation.card.rows == [
             %{
               id: "mission-row-mission-alpha",
               display_name: "Alpha Mission",
               slug: "alpha",
               spacecraft_count: 0,
               status: "info",
               status_label: "No spacecraft",
               href: "/missions/mission-alpha"
             },
             %{
               id: "mission-row-mission-beta",
               display_name: "Beta Mission",
               slug: "beta",
               spacecraft_count: 2,
               status: "ready",
               status_label: "Ready",
               href: "/missions/mission-beta"
             },
             %{
               id: "mission-row-mission-gamma",
               display_name: "Gamma Mission",
               slug: "gamma",
               spacecraft_count: 1,
               status: "attention",
               status_label: "Needs setup",
               href: "/missions/mission-gamma"
             }
           ]
  end

  test "raw attrs preserve HEEx nil false true string and number semantics" do
    assert Presentation.raw_attrs(%{
             "data-nil" => nil,
             "data-false" => false,
             "data-true" => true,
             "data-string" => "retained",
             "data-number" => 42
           }) == %{
             "data-true" => "",
             "data-string" => "retained",
             "data-number" => "42"
           }
  end

  defp mission_row(mission_id, display_name, slug, spacecraft_count, status, status_label) do
    %{
      mission: %{mission_id: mission_id, display_name: display_name, slug: slug},
      spacecraft_count: spacecraft_count,
      status: status,
      status_label: status_label
    }
  end
end
