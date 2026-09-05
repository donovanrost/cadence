defmodule CadenceWeb.SpacecraftTypeListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    profiles =
      Cadence.SpacecraftTypeStore.list_spacecraft_types(organization_id, mission.mission_id)

    spacecraft_profile_rows =
      Enum.map(profiles, &spacecraft_profile_row_dto(&1, mission.mission_id))

    spacecraft_profile_count = length(profiles)
    spacecraft_profiles_empty? = profiles == []

    {:ok,
     socket
     |> assign(:page_title, "Spacecraft Profiles")
     |> assign(:nav_item, :spacecraft)
     |> assign(:spacecraft_profile_count, spacecraft_profile_count)
     |> assign(:spacecraft_profiles_empty?, spacecraft_profiles_empty?)
     |> assign(:spacecraft_profile_rows, spacecraft_profile_rows)
     |> assign(
       :presentation,
       spacecraft_type_list_presentation(
         mission,
         spacecraft_profile_count,
         spacecraft_profiles_empty?,
         spacecraft_profile_rows
       )
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="spacecraft-type-list-page-component"
        v-component="FederatedFullPageSurface"
        application_key="spacecraft"
        surface_id="profile_list"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
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

  defp spacecraft_type_list_presentation(
         mission,
         spacecraft_profile_count,
         spacecraft_profiles_empty?,
         rows
       ) do
    new_profile_path = ~p"/missions/#{mission.mission_id}/spacecraft/profiles/new"

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "spacecraft-profiles-page",
            "class" => "space-y-6"
          })
      },
      "header" => header_presentation(mission, spacecraft_profile_count, new_profile_path),
      "empty_state" => empty_state_presentation(spacecraft_profiles_empty?, new_profile_path),
      "card" => card_presentation(spacecraft_profiles_empty?, rows)
    }
  end

  defp header_presentation(mission, spacecraft_profile_count, new_profile_path) do
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
        "text" => "Spacecraft Profiles",
        "suffix" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "ml-3 font-mono text-base text-base-content/60"
            }),
          "text" => "#{spacecraft_profile_count} defined"
        }
      },
      "subtitle" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
          }),
        "text" =>
          "Reusable byte-interpretation contracts for spacecraft that share bus protocols, frame parameters, and platform applications."
      },
      "actions" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-center gap-2"}),
        "new_profile" => %{
          "attrs" =>
            navigate_attrs(new_profile_path, %{
              "id" => "new-spacecraft-profile-link",
              "class" => "btn btn-primary btn-sm gap-1"
            }),
          "icon" => %{
            "attrs" => presentation_attrs(%{"class" => "hero-plus h-4 w-4"})
          },
          "text" => "New Profile"
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
          "key" => "spacecraft",
          "separator" => breadcrumb_separator(),
          "link" => %{
            "attrs" =>
              navigate_attrs(~p"/missions/#{mission.mission_id}/spacecraft", %{
                "class" => "hover:text-primary transition-colors"
              }),
            "text" => "Spacecraft"
          },
          "current" => nil
        },
        %{
          "key" => "spacecraft-profiles",
          "separator" => breadcrumb_separator(),
          "link" => nil,
          "current" => %{
            "attrs" => presentation_attrs(%{"class" => "text-primary/90"}),
            "text" => "Spacecraft Profiles"
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

  defp empty_state_presentation(true, new_profile_path) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" =>
            "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
        }),
      "title" => %{
        "attrs" => presentation_attrs(%{"class" => "hud-label"}),
        "text" => "No profiles yet"
      },
      "description" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
          }),
        "text" =>
          "Define a profile to capture the protocol stack and applications shared by a set of spacecraft."
      },
      "action_container" => %{
        "attrs" => presentation_attrs(%{"class" => "mt-5"})
      },
      "action" => %{
        "attrs" => navigate_attrs(new_profile_path, %{"class" => "btn btn-primary btn-sm"}),
        "icon" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"
            })
        },
        "text" => "Create the first profile"
      }
    }
  end

  defp empty_state_presentation(false, _new_profile_path), do: nil

  defp card_presentation(true, _rows), do: nil

  defp card_presentation(false, rows) do
    %{
      "attrs" => presentation_attrs(%{"class" => "card bg-base-200 border border-base-300"}),
      "body" => %{
        "attrs" => presentation_attrs(%{"class" => "card-body p-0"})
      },
      "list_component" => %{
        "attrs" => presentation_attrs(%{"id" => "spacecraft-profiles-list-component"})
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

  defp spacecraft_profile_row_dto(profile, mission_id) do
    %{
      id: "spacecraft-profile-#{profile.spacecraft_type_id}",
      display_name: profile.display_name,
      version: "v#{profile.version}",
      downlink_protocol: protocol_label(profile.downlink_protocol),
      uplink_protocol: protocol_label(profile.uplink_protocol),
      applications: applications_summary(profile.applications),
      href: ~p"/missions/#{mission_id}/spacecraft/profiles/#{profile.spacecraft_type_id}"
    }
  end

  defp protocol_label(protocol) when is_atom(protocol) do
    protocol
    |> Atom.to_string()
    |> String.upcase()
  end

  defp protocol_label(protocol) when is_binary(protocol), do: String.upcase(protocol)

  defp applications_summary(applications)
       when is_map(applications) and map_size(applications) > 0 do
    applications
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map_join(", ", &humanize_application_key/1)
  end

  defp applications_summary(_), do: "None"

  defp humanize_application_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp humanize_application_key(key) when is_binary(key) do
    key
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
