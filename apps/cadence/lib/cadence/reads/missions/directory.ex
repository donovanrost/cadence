defmodule Cadence.Reads.Missions.Directory do
  @moduledoc "Core mission directory presentation."
  alias Cadence.{Missions, SpacecraftStore}

  def load(organization_id) do
    rows =
      organization_id
      |> Missions.list_missions()
      |> Enum.map(fn mission ->
        spacecraft = SpacecraftStore.list_spacecraft(organization_id, mission.mission_id)
        ready? = spacecraft != [] and Enum.all?(spacecraft, &is_integer(&1.scid))

        %{
          "id" => "mission-row-#{mission.mission_id}",
          "display_name" => mission.display_name,
          "slug" => mission.slug,
          "spacecraft_count" => length(spacecraft),
          "status" =>
            if(spacecraft == [], do: "info", else: if(ready?, do: "ready", else: "attention")),
          "status_label" =>
            cond do
              spacecraft == [] -> "No spacecraft"
              ready? -> "Ready"
              true -> "Needs setup"
            end,
          "href" => mission_href(mission.mission_id)
        }
      end)

    {:ok,
     %{
       "presentation" => %{
         "root_class" => "space-y-6",
         "header" => %{
           "class" => "border-b border-primary/20 pb-4",
           "content_class" => "flex items-end justify-between gap-4",
           "eyebrow" => %{"class" => "hud-label", "text" => "Organization"},
           "title" => %{
             "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight",
             "text" => "Missions",
             "suffix" => %{
               "class" => "ml-3 font-mono text-base text-base-content/60",
               "text" => "#{length(rows)} configured"
             }
           },
           "actions_class" => "flex items-center gap-2",
           "action" => %{
             "attrs" => navigate_attrs("/missions/new"),
             "class" => "btn btn-primary btn-sm gap-1",
             "icon_class" => "hero-plus h-4 w-4",
             "label" => "New Mission"
           }
         },
         "empty_state" => %{
           "visible" => rows == [],
           "id" => "mission-list-empty-state",
           "class" =>
             "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
           "icon_class" => "hero-rocket-launch mx-auto h-10 w-10 text-base-content/30 block",
           "title" => %{"class" => "hud-label mt-3", "text" => "No missions yet"},
           "description" => %{
             "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70",
             "text" => "Create your first mission to get started."
           },
           "action_container_class" => "mt-5",
           "action" => %{
             "attrs" => navigate_attrs("/missions/new"),
             "class" => "btn btn-primary btn-sm gap-1",
             "icon_class" => "hero-plus h-4 w-4",
             "label" => "Create Mission"
           }
         },
         "card" => %{
           "visible" => rows != [],
           "class" => "card bg-base-200 border border-base-300",
           "body_class" => "card-body p-0",
           "rows" => rows
         }
       }
     }}
  end

  defp mission_href(id), do: "/missions/#{id}"

  defp navigate_attrs(href),
    do: %{"href" => href, "data-phx-link" => "redirect", "data-phx-link-state" => "push"}
end
