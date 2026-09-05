defmodule CadenceWeb.CatalogIndexLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Catalog
  alias Cadence.Catalog.Events

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    if connected?(socket), do: Events.subscribe_import_runs(mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Catalog")
     |> assign(:nav_item, :catalog)
     |> assign_databases(organization_id, mission.mission_id)}
  end

  @impl true
  def handle_info({event, _run}, socket)
      when event in [
             :import_run_started,
             :import_run_updated,
             :import_run_completed,
             :import_run_failed
           ] do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    {:noreply, assign_databases(socket, organization_id, mission.mission_id)}
  end

  defp assign_databases(socket, organization_id, mission_id) do
    databases = Catalog.list_databases(organization_id, mission_id)
    latest_revisions = Catalog.latest_revision_by_database(organization_id, mission_id)
    latest_runs = Catalog.latest_import_run_by_database(organization_id, mission_id)

    rows =
      Enum.map(databases, &database_table_row(&1, mission_id, latest_revisions, latest_runs))

    assign(
      socket,
      :catalog_index_presentation,
      page_presentation_dto(socket.assigns.current_mission, rows)
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="catalog-index-component"
        v-component="FederatedFullPageSurface"
        presentation={@catalog_index_presentation}
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

  defp page_presentation_dto(mission, rows) do
    %{
      "root" => %{
        "attrs" => presentation_attrs(%{"class" => "space-y-6"})
      },
      "header" => %{
        "attrs" => presentation_attrs(%{"class" => "border-b border-primary/20 pb-4"}),
        "body" => %{
          "attrs" => presentation_attrs(%{"class" => "flex items-end justify-between gap-4"})
        },
        "content" => %{"attrs" => presentation_attrs(%{})},
        "breadcrumbs" => %{
          "attrs" =>
            presentation_attrs(%{
              "aria-label" => "Breadcrumb",
              "class" =>
                "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
            }),
          "mission" => %{
            "attrs" =>
              navigate_attrs(
                ~p"/missions/#{mission.mission_id}",
                %{"class" => "hover:text-primary transition-colors"}
              ),
            "text" => mission.display_name
          },
          "separator" => %{
            "attrs" =>
              presentation_attrs(%{
                "aria-hidden" => "true",
                "class" => "text-base-content/20"
              }),
            "text" => "/"
          },
          "current" => %{
            "attrs" => presentation_attrs(%{"class" => "text-primary/90"}),
            "text" => "Catalog"
          }
        },
        "title" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
            }),
          "text" => "Catalog"
        },
        "subtitle" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
            }),
          "text" =>
            "Mission database library. Revisions are imported here; runtime usage is selected later."
        },
        "actions" => %{
          "attrs" => presentation_attrs(%{"class" => "flex items-center gap-2"})
        },
        "new_database" => %{
          "attrs" =>
            navigate_attrs(
              ~p"/missions/#{mission.mission_id}/catalog/new",
              %{"class" => "btn btn-primary btn-sm gap-1", "id" => "new-database-link"}
            ),
          "icon" => %{
            "attrs" => presentation_attrs(%{"class" => "hero-plus h-4 w-4"})
          },
          "text" => "New database"
        }
      },
      "empty_state" => %{
        "visible" => rows == [],
        "list" => %{
          "attrs" => presentation_attrs(%{"id" => "catalog-database-list"})
        },
        "root" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" =>
                "rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
            })
        },
        "title" => %{
          "attrs" => presentation_attrs(%{"class" => "hud-label"}),
          "text" => "No catalog databases yet"
        },
        "description" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "mt-2 max-w-md mx-auto text-sm text-base-content/70"
            }),
          "text" => "Use + New database above to import the first revision."
        }
      },
      "card" => %{
        "visible" => rows != [],
        "root" => %{
          "attrs" =>
            presentation_attrs(%{
              "class" => "card bg-base-200 border border-base-300",
              "id" => "catalog-database-list"
            })
        },
        "body" => %{
          "attrs" => presentation_attrs(%{"class" => "card-body p-0"})
        },
        "child_wrapper" => %{
          "attrs" => presentation_attrs(%{"id" => "catalog-databases-table-component"})
        },
        "rows" => rows
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

  defp database_table_row(database, mission_id, latest_revisions, latest_runs) do
    database_id = database.catalog_database_id
    revision = Map.get(latest_revisions, database_id)
    run = Map.get(latest_runs, database_id)

    %{
      "id" => "catalog-database-row-#{database_id}",
      "actions_id" => "#{database_id}-actions",
      "name" => database.name,
      "slug" => database.slug,
      "href" => ~p"/missions/#{mission_id}/catalog/databases/#{database_id}",
      "latest_revision" => latest_revision_dto(revision, mission_id),
      "latest_import" => latest_import_dto(run, mission_id)
    }
  end

  defp latest_revision_dto(nil, _mission_id), do: nil

  defp latest_revision_dto(revision, mission_id) do
    %{
      "label" => revision.revision_label,
      "href" => ~p"/missions/#{mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
    }
  end

  defp latest_import_dto(nil, _mission_id), do: nil

  defp latest_import_dto(run, mission_id) do
    %{
      "status" => import_status_badge(run.status),
      "status_label" => import_status_label(run.status),
      "href" => ~p"/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
    }
  end

  defp import_status_badge(:running), do: "info"
  defp import_status_badge(:completed), do: "ready"
  defp import_status_badge(:failed), do: "blocked"
  defp import_status_badge(_status), do: "info"

  defp import_status_label(:running), do: "Running"
  defp import_status_label(:completed), do: "Completed"
  defp import_status_label(:failed), do: "Failed"
  defp import_status_label(status), do: status |> to_string() |> String.capitalize()
end
