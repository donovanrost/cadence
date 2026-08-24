defmodule CadenceWeb.MissionListLive.Presentation do
  @moduledoc false
  use CadenceWeb, :html

  @doc false
  def build(mission_rows) do
    rows = Enum.map(mission_rows, &mission_table_row/1)
    new_mission_attrs = navigate_attrs(~p"/missions/new")

    %{
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
            text: "#{length(rows)} configured"
          }
        },
        actions_class: "flex items-center gap-2",
        action: %{
          attrs: new_mission_attrs,
          class: "btn btn-primary btn-sm gap-1",
          icon_class: "hero-plus h-4 w-4",
          label: "New Mission"
        }
      },
      empty_state: %{
        visible: rows == [],
        id: "mission-list-empty-state",
        class: "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center",
        icon_class: "hero-rocket-launch mx-auto h-10 w-10 text-base-content/30 block",
        title: %{class: "hud-label mt-3", text: "No missions yet"},
        description: %{
          class: "mt-2 max-w-md mx-auto text-sm text-base-content/70",
          text: "Create your first mission to get started."
        },
        action_container_class: "mt-5",
        action: %{
          attrs: new_mission_attrs,
          class: "btn btn-primary btn-sm",
          icon_class: "hero-plus -ml-0.5 mr-1 h-4 w-4",
          label: "New Mission"
        }
      },
      card: %{
        visible: rows != [],
        class: "card bg-base-200 border border-base-300",
        body_class: "card-body p-0",
        rows: rows
      }
    }
  end

  @doc false
  def raw_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_name, value}, rendered when value in [nil, false] ->
        rendered

      {name, true}, rendered ->
        Map.put(rendered, name, "")

      {name, value}, rendered ->
        Map.put(rendered, name, to_string(value))
    end)
  end

  defp navigate_attrs(href) do
    raw_attrs(%{
      "data-phx-link" => "redirect",
      "data-phx-link-state" => "push",
      "href" => href
    })
  end

  defp mission_table_row(row) do
    %{
      id: "mission-row-#{row.mission.mission_id}",
      display_name: row.mission.display_name,
      slug: row.mission.slug,
      spacecraft_count: row.spacecraft_count,
      status: Atom.to_string(row.status),
      status_label: row.status_label,
      href: ~p"/missions/#{row.mission.mission_id}"
    }
  end
end
