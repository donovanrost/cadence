defmodule CadenceWeb.CommsGroundStationListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.GroundStationStore

  alias CadenceWeb.ListParams

  @page_size 50
  @sortable ~w(display_name)

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    ground_stations =
      GroundStationStore.list_ground_stations(
        scope.organization_id,
        mission.mission_id
      )

    {:ok,
     socket
     |> assign(:page_title, "Ground Stations")
     |> assign(:nav_item, :comms_ground_stations)
     |> assign(:ground_stations, ground_stations)
     |> assign(:ground_station_count, length(ground_stations))
     |> assign(:ground_stations_empty?, ground_stations == [])
     |> assign(:presentation, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    list = ListParams.parse(params, sortable: @sortable, default_sort: "display_name")
    {visible, total} = filter_ground_stations(socket.assigns.ground_stations, list)
    mission_id = socket.assigns.current_mission.mission_id
    sort_dir = Atom.to_string(list.dir)
    rows = Enum.map(visible, &ground_station_table_row(&1, mission_id))

    presentation =
      page_presentation_dto(
        socket.assigns.current_mission,
        socket.assigns.ground_station_count,
        socket.assigns.ground_stations_empty?,
        rows,
        list,
        sort_dir,
        total
      )

    {:noreply,
     socket
     |> assign(:list, list)
     |> assign(:ground_station_sort_dir, sort_dir)
     |> assign(:filtered_count, total)
     |> assign(:ground_station_table_rows, rows)
     |> assign(:presentation, presentation)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, patch_list(socket, %{socket.assigns.list | q: q, page: 1})}
  end

  @impl true
  def handle_event("sort", %{"sort" => key}, socket) when key in @sortable do
    {:noreply, patch_list(socket, ListParams.toggle_sort(socket.assigns.list, key))}
  end

  @impl true
  def handle_event("paginate", %{"page" => page}, socket) do
    list = %{socket.assigns.list | page: ListParams.parse(%{"page" => page}, sortable: []).page}
    {:noreply, patch_list(socket, list)}
  end

  defp patch_list(socket, list) do
    mission_id = socket.assigns.current_mission.mission_id
    query = ListParams.to_query(list)
    push_patch(socket, to: ~p"/missions/#{mission_id}/comms/ground-stations?#{query}")
  end

  defp filter_ground_stations(ground_stations, %ListParams{} = list) do
    matching =
      ground_stations
      |> Enum.filter(&matches_query?(&1, list.q))
      |> Enum.sort_by(&String.downcase(&1.display_name), list.dir)

    last_page = max(ceil(length(matching) / @page_size), 1)
    page = min(list.page, last_page)
    visible = Enum.slice(matching, (page - 1) * @page_size, @page_size)
    {visible, length(matching)}
  end

  defp matches_query?(_ground_station, nil), do: true

  defp matches_query?(ground_station, q) do
    downcased = String.downcase(q)

    Enum.any?(
      [
        ground_station.display_name,
        ground_station.ground_station_id,
        ground_station.provider,
        ground_station.region
      ],
      &(is_binary(&1) and String.contains?(String.downcase(&1), downcased))
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-ground-station-list-page-component"
        v-component="CommsGroundStationListPage"
        presentation={@presentation}
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

  defp page_presentation_dto(
         mission,
         ground_station_count,
         ground_stations_empty?,
         rows,
         list,
         sort_dir,
         filtered_count
       ) do
    new_ground_station_path =
      ~p"/missions/#{mission.mission_id}/comms/ground-stations/new"

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "comms-ground-stations-page",
            "class" => "space-y-6"
          })
      },
      "header" => header_presentation(mission, ground_station_count, new_ground_station_path),
      "empty_state" => empty_state_presentation(ground_stations_empty?, new_ground_station_path),
      "card" =>
        card_presentation(
          ground_stations_empty?,
          rows,
          list,
          sort_dir,
          filtered_count
        )
    }
  end

  defp header_presentation(mission, ground_station_count, new_ground_station_path) do
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
        "text" => "Ground Stations",
        "suffix" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "ml-3 font-mono text-base text-base-content/60"
            }),
          "text" => "#{ground_station_count} configured"
        }
      },
      "subtitle" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
          }),
        "text" =>
          "Mission-owned antenna and site identities used by dashboard scope, source diagnostics, and comms setup."
      },
      "actions" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-center gap-2"}),
        "new_ground_station" => %{
          "attrs" =>
            navigate_attrs(new_ground_station_path, %{
              "id" => "new-ground-station-link",
              "class" => "btn btn-primary btn-sm"
            }),
          "text" => "New Ground Station"
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
          "key" => "ground-stations",
          "separator" => breadcrumb_separator(),
          "link" => nil,
          "current" => %{
            "attrs" => presentation_attrs(%{"class" => "text-primary/90"}),
            "text" => "Ground Stations"
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

  defp empty_state_presentation(true, new_ground_station_path) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" =>
            "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
        }),
      "title" => %{
        "attrs" => presentation_attrs(%{"class" => "hud-label"}),
        "text" => "No ground stations"
      },
      "description" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
          }),
        "text" =>
          "Create a setup record before linking telemetry diagnostics to a stable station identity."
      },
      "action_container" => %{
        "attrs" => presentation_attrs(%{"class" => "mt-5"})
      },
      "action" => %{
        "attrs" =>
          navigate_attrs(new_ground_station_path, %{"class" => "btn btn-primary btn-sm"}),
        "icon" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"
            })
        },
        "text" => "New Ground Station"
      }
    }
  end

  defp empty_state_presentation(false, _new_ground_station_path), do: nil

  defp card_presentation(true, _rows, _list, _sort_dir, _filtered_count), do: nil

  defp card_presentation(false, rows, list, sort_dir, filtered_count) do
    %{
      "attrs" => presentation_attrs(%{"class" => "card bg-base-200 border border-base-300"}),
      "body" => %{
        "attrs" => presentation_attrs(%{"class" => "card-body p-0"})
      },
      "list_component" => %{
        "attrs" => presentation_attrs(%{"id" => "ground-stations-list-component"}),
        "props" => %{
          "rows" => rows,
          "search" => list.q,
          "sort" => list.sort,
          "sort_dir" => sort_dir,
          "page" => list.page,
          "page_size" => @page_size,
          "total_count" => filtered_count
        }
      }
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

  defp ground_station_table_row(ground_station, mission_id) do
    %{
      id: "ground-station-#{ground_station.ground_station_id}",
      display_name: ground_station.display_name,
      provider: ground_station.provider || "UNSPECIFIED",
      region: ground_station.region || "none",
      ground_station_id: ground_station.ground_station_id,
      href: ~p"/missions/#{mission_id}/comms/ground-stations/#{ground_station.ground_station_id}"
    }
  end
end
