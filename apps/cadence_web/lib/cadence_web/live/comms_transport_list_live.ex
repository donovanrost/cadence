defmodule CadenceWeb.CommsTransportListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.TransportKind
  alias CadenceWeb.ListParams

  # Search/sort/paginate happen in memory: TransportStore dedupes latest
  # versions in Elixir, and transports number in the tens per mission.
  # Move to DB-side paging (the list_spacecraft_page pattern) only if
  # transports ever stop fitting comfortably in one query.
  @page_size 50
  @sortable ~w(display_name)

  @impl true
  def mount(_params, _session, socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    transports =
      TransportStore.list_transports(scope.organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Comms Transports")
     |> assign(:nav_item, :comms_transports)
     |> assign(:transports, transports)
     |> assign(:transport_count, length(transports))
     |> assign(:transports_empty?, transports == [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    list = ListParams.parse(params, sortable: @sortable, default_sort: "display_name")
    {visible, total} = filter_transports(socket.assigns.transports, list)
    mission = socket.assigns.current_mission

    rows = Enum.map(visible, &transport_table_row(&1, mission.mission_id))

    presentation =
      page_presentation_dto(
        mission,
        socket.assigns.transport_count,
        socket.assigns.transports_empty?,
        rows,
        list,
        total
      )

    {:noreply,
     socket
     |> assign(:list, list)
     |> assign(:transport_sort_dir, Atom.to_string(list.dir))
     |> assign(:filtered_count, total)
     |> assign(:transport_table_rows, rows)
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
    push_patch(socket, to: ~p"/missions/#{mission_id}/comms/transports?#{query}")
  end

  defp filter_transports(transports, %ListParams{} = list) do
    matching =
      transports
      |> Enum.filter(&matches_query?(&1, list.q))
      |> Enum.sort_by(&String.downcase(&1.display_name), list.dir)

    last_page = max(ceil(length(matching) / @page_size), 1)
    page = min(list.page, last_page)
    visible = Enum.slice(matching, (page - 1) * @page_size, @page_size)
    {visible, length(matching)}
  end

  defp matches_query?(_transport, nil), do: true

  defp matches_query?(transport, q) do
    String.contains?(String.downcase(transport.display_name), String.downcase(q))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="comms-transport-list-page-component"
        v-component="FederatedFullPageSurface"
        application_key="comms"
        surface_id="transports"
          host_scope="mission"
          mission_id={@current_mission.mission_id}
          query_params={%{mission_id: @current_mission.mission_id}}
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

  defp page_presentation_dto(mission, transport_count, transports_empty?, rows, list, total) do
    new_transport_path = ~p"/missions/#{mission.mission_id}/comms/transports/new"

    %{
      "root" => %{
        "attrs" =>
          presentation_attrs(%{
            "id" => "comms-transports-page",
            "class" => "space-y-6"
          })
      },
      "header" => header_presentation(mission, transport_count, new_transport_path),
      "empty_state" => empty_state_presentation(transports_empty?, new_transport_path),
      "card" => card_presentation(transports_empty?, rows, list, total)
    }
  end

  defp header_presentation(mission, transport_count, new_transport_path) do
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
        "text" => "Transports",
        "suffix" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "ml-3 font-mono text-base text-base-content/60"
            }),
          "text" => "#{transport_count} configured"
        }
      },
      "subtitle" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
          }),
        "text" =>
          "Durable byte-moving capabilities Cadence can use for inbound, outbound, or bidirectional spacecraft traffic."
      },
      "actions" => %{
        "attrs" => presentation_attrs(%{"class" => "flex items-center gap-2"}),
        "new_transport" => %{
          "attrs" =>
            navigate_attrs(new_transport_path, %{
              "id" => "new-transport-link",
              "class" => "btn btn-primary btn-sm gap-1"
            }),
          "icon" => %{
            "attrs" => presentation_attrs(%{"class" => "hero-plus h-4 w-4"})
          },
          "text" => "New Transport"
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
          "key" => "transports",
          "separator" => breadcrumb_separator(),
          "link" => nil,
          "current" => %{
            "attrs" => presentation_attrs(%{"class" => "text-primary/90"}),
            "text" => "Transports"
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

  defp empty_state_presentation(true, new_transport_path) do
    %{
      "attrs" =>
        presentation_attrs(%{
          "class" =>
            "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
        }),
      "title" => %{
        "attrs" => presentation_attrs(%{"class" => "hud-label"}),
        "text" => "No transports"
      },
      "description" => %{
        "attrs" =>
          presentation_attrs(%{
            "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
          }),
        "text" => "Create a transport to describe an external capability for moving bytes."
      },
      "action_container" => %{
        "attrs" => presentation_attrs(%{"class" => "mt-5"})
      },
      "action" => %{
        "attrs" => navigate_attrs(new_transport_path, %{"class" => "btn btn-primary btn-sm"}),
        "icon" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "hero-plus -ml-0.5 mr-1 h-4 w-4"
            })
        },
        "text" => "Create the first transport"
      }
    }
  end

  defp empty_state_presentation(false, _new_transport_path), do: nil

  defp card_presentation(true, _rows, _list, _total), do: nil

  defp card_presentation(false, rows, list, total) do
    %{
      "attrs" => presentation_attrs(%{"class" => "card bg-base-200 border border-base-300"}),
      "body" => %{
        "attrs" => presentation_attrs(%{"class" => "card-body p-0"})
      },
      "list_component" => %{
        "attrs" => presentation_attrs(%{"id" => "transports-list-component"}),
        "props" => %{
          "rows" => rows,
          "search" => list.q,
          "sort" => list.sort,
          "sort_dir" => Atom.to_string(list.dir),
          "page" => list.page,
          "page_size" => @page_size,
          "total_count" => total
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

  defp transport_summary(transport) do
    {:ok, entry} = TransportKind.fetch(transport.transport_kind)
    entry.module.display_summary(transport.configuration)
  end

  defp transport_table_row(transport, mission_id) do
    transport_id = transport.transport_id

    %{
      id: "transport-#{transport_id}",
      transport_id: transport_id,
      display_name: transport.display_name,
      origin: origin_label(transport.origin),
      origin_id: "transport-origin-#{transport_id}",
      provider: provider_label(transport),
      provider_dom_id: "transport-provider-#{transport_id}",
      operator_summary: operator_summary(transport),
      operator_summary_id: "transport-operator-summary-#{transport_id}",
      endpoint: transport_summary(transport).endpoint,
      readiness_status: transport |> readiness_status() |> Atom.to_string(),
      readiness_label: readiness_label(transport),
      readiness_id: "transport-readiness-#{transport_id}",
      version: "v#{transport.version}",
      href: ~p"/missions/#{mission_id}/comms/transports/#{transport_id}"
    }
  end

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()
  end

  defp origin_label(:provider_managed), do: "Provider managed"
  defp origin_label(:direct), do: "Direct"

  defp provider_label(%{origin: :provider_managed} = transport) do
    get_in(transport.provider_configuration_snapshot, ["provider", "display_name"]) ||
      transport.mission_provider_id
  end

  defp provider_label(_transport), do: "Cadence"

  defp operator_summary(%{origin: :provider_managed} = transport) do
    get_in(transport.provider_configuration_snapshot, ["delivery_profile", "operator_summary"]) ||
      "Provider-managed delivery"
  end

  defp operator_summary(transport), do: "Direct #{human_atom(transport.transport_kind)}"

  defp readiness_status(%{origin: :provider_managed} = transport) do
    if get_in(transport.provider_configuration_snapshot, ["delivery_profile", "state"]) == "ready",
      do: :ready,
      else: :attention
  end

  defp readiness_status(_transport), do: :info

  defp readiness_label(%{origin: :provider_managed} = transport) do
    if readiness_status(transport) == :ready, do: "Ready", else: "Profile drift"
  end

  defp readiness_label(_transport), do: "Configured"
end
