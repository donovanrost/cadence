defmodule CadenceWeb.OrganizationHomeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @recent_mission_limit 3

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    summary = load_summary(org.organization_id)

    {:ok,
     socket
     |> assign(:page_title, org.display_name)
     |> assign(:nav_item, :organization_home)
     |> assign(:presentation, presentation_dto(org, summary))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="organization-home-component"
        v-component="FederatedFullPageSurface"
        application_key="organization_admin"
        surface_id="organization_home"
        host_scope="organization"
        organization_id={@current_scope.organization.organization_id}
        query_params={%{organization_id: @current_scope.organization.organization_id}}
        v-ssr={false}
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

  defp presentation_dto(org, summary) do
    %{
      "root" => %{
        "attrs" => presentation_attrs(%{"class" => "space-y-6"})
      },
      "header" => %{
        "attrs" => presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
        "body" => %{"attrs" => %{}},
        "content" => %{"attrs" => %{}},
        "title" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
            }),
          "text" => org.display_name
        },
        "subtitle" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
            }),
          "text" => org.slug
        }
      },
      "stats" => %{
        "mission_count" => summary.mission_count,
        "spacecraft_count" => summary.spacecraft_count,
        "member_count" => summary.member_count
      },
      "recent_missions" => recent_missions_presentation(summary.recent_missions)
    }
  end

  defp recent_missions_presentation(recent_missions) do
    %{
      "card" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "card bg-base-200 border border-base-300",
            "id" => "organization-recent-missions"
          })
      },
      "body" => %{
        "attrs" => presentation_attrs(%{"class" => "card-body p-6"})
      },
      "header" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-start justify-between gap-4"}),
        "content" => %{"attrs" => %{}},
        "eyebrow" => %{
          "attrs" => presentation_attrs(%{"class" => "hud-label mb-2"}),
          "text" => "Recent Missions"
        },
        "title" => %{
          "attrs" => presentation_attrs(%{"class" => "text-lg font-semibold"}),
          "text" => "Jump into a mission"
        },
        "actions" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "flex flex-wrap items-center justify-end gap-2"
            })
        },
        "all_missions" => %{
          "attrs" => navigate_attrs(~p"/missions", %{"class" => "btn btn-ghost btn-sm"}),
          "text" => "All missions"
        }
      },
      "empty_state" => empty_state_presentation(recent_missions),
      "rows" => Enum.map(recent_missions, &recent_mission_row/1)
    }
  end

  defp empty_state_presentation([]) do
    %{
      "container" => %{
        "attrs" => presentation_attrs(%{"class" => "mt-6"})
      },
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" =>
              "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
          })
      },
      "icon" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "hero-rocket-launch mx-auto h-10 w-10 text-base-content/30 block"
          })
      },
      "title" => %{
        "attrs" => presentation_attrs(%{"class" => "hud-label mt-3"}),
        "text" => "No missions yet"
      },
      "description" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
          }),
        "text" => "Create your first mission to get started."
      },
      "action_container" => %{
        "attrs" => presentation_attrs(%{"class" => "mt-5"})
      },
      "action" => %{
        "attrs" => navigate_attrs(~p"/missions/new", %{"class" => "btn btn-primary btn-sm"}),
        "text" => "New Mission"
      },
      "action_icon" => %{
        "attrs" => presentation_attrs(%{"class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"})
      }
    }
  end

  defp empty_state_presentation(_recent_missions), do: nil

  defp load_summary(organization_id) do
    missions = Cadence.Missions.list_missions(organization_id)
    members = Cadence.Accounts.list_organization_members(organization_id)

    mission_summaries =
      Enum.map(missions, fn mission ->
        spacecraft = Cadence.SpacecraftStore.list_spacecraft(organization_id, mission.mission_id)
        Map.put(mission_status(spacecraft), :mission, mission)
      end)

    %{
      mission_count: length(missions),
      member_count: length(members),
      spacecraft_count: Enum.sum(Enum.map(mission_summaries, & &1.spacecraft_count)),
      recent_missions: Enum.take(mission_summaries, @recent_mission_limit)
    }
  end

  defp mission_status(spacecraft) do
    cond do
      spacecraft == [] ->
        %{spacecraft_count: 0, status: :info, status_label: "No spacecraft"}

      Enum.all?(spacecraft, & &1.scid) ->
        %{spacecraft_count: length(spacecraft), status: :ready, status_label: "Ready"}

      true ->
        %{spacecraft_count: length(spacecraft), status: :attention, status_label: "Needs setup"}
    end
  end

  defp recent_mission_row(row) do
    href = ~p"/missions/#{row.mission.mission_id}"

    %{
      "id" => "organization-recent-mission-#{row.mission.mission_id}",
      "display_name" => row.mission.display_name,
      "slug" => row.mission.slug,
      "status" => Atom.to_string(row.status),
      "status_label" => row.status_label,
      "href" => href
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
end
