defmodule CadenceWeb.OpsDashboardListLive do
  @moduledoc """
  Searchable dashboard directory with mission-shared lifecycle metadata and
  user-scoped stars and recency.
  """

  use CadenceWeb, :live_view

  alias CadenceWeb.OpsShellHook

  @filter_keys ~w(query lifecycle tag sort)
  @default_filters %{"query" => "", "lifecycle" => "active", "tag" => "all", "sort" => "updated"}

  @impl true
  def mount(_params, _session, socket) do
    mission_id = socket.assigns.current_mission.mission_id

    {:ok,
     socket
     |> stream_configure(:dashboard_directory,
       dom_id: &"dashboard-directory-row-#{&1.dashboard_id}"
     )
     |> assign(:page_title, "Dashboard Directory")
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:archived_dashboards, [])
     |> assign(:directory_filters, @default_filters)
     |> assign(:directory_form, to_form(@default_filters, as: :directory))
     |> assign(:directory_tags, [])
     |> assign(:directory_count, 0)
     |> assign(:directory_empty?, true)
     |> assign(
       :dashboard_directory_page,
       directory_page_dto(mission_id, socket.assigns.dashboard_author?, 0)
     )
     |> assign(:dashboard_directory_filters, directory_filters_dto(@default_filters, []))
     |> stream(:dashboard_directory, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = normalize_filters(params)

    {:noreply,
     socket
     |> assign(:directory_filters, filters)
     |> assign(:directory_form, to_form(filters, as: :directory))
     |> reload_directory()}
  end

  @impl true
  def handle_event("filter_dashboards", %{"directory" => params}, socket) do
    {:noreply,
     push_patch(socket,
       to: directory_path(socket.assigns.current_mission.mission_id, normalize_filters(params))
     )}
  end

  def handle_event("toggle_dashboard_star", params, socket) do
    dashboard_id = params["dashboard-id"]
    starred = params["starred"] == "true"
    %{current_scope: scope, current_mission: mission} = socket.assigns

    case current_user_id(scope) do
      user_id when is_binary(user_id) ->
        case Cadence.Dashboards.set_dashboard_starred(
               scope.organization_id,
               mission.mission_id,
               user_id,
               dashboard_id,
               starred
             ) do
          {:ok, _preference} ->
            {:noreply, reload_directory(socket)}

          {:error, :dashboard_not_found} ->
            {:noreply,
             socket
             |> reload_directory()
             |> put_flash(:error, "Dashboard is no longer available.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to update star: #{inspect(reason)}")}
        end

      _missing_user ->
        {:noreply, put_flash(socket, :error, "Sign in to manage dashboard stars.")}
    end
  end

  def handle_event("restore_dashboard", params, socket) do
    dashboard_id = params["dashboard-id"]
    %{current_scope: scope, current_mission: mission} = socket.assigns

    with {:ok, summary} <- validate_restore_available(socket, dashboard_id),
         {:ok, expected_version} <- restore_expected_version(params, summary),
         :ok <-
           Cadence.Dashboards.restore_document(
             scope.organization_id,
             mission.mission_id,
             dashboard_id,
             expected_version: expected_version,
             actor_id: current_user_id(scope)
           ) do
      {:noreply,
       socket
       |> reload_directory()
       |> put_flash(:info, "Dashboard restored.")}
    else
      {:error, :dashboard_restore_not_available} ->
        {:noreply,
         socket
         |> reload_directory()
         |> put_flash(:info, "Dashboard is already active.")}

      {:error, :dashboard_not_found} ->
        {:noreply,
         socket
         |> reload_directory()
         |> put_flash(:error, "Dashboard not found.")}

      {:error, {:dashboard_version_conflict, current_version}} ->
        {:noreply,
         socket
         |> reload_directory()
         |> put_flash(
           :error,
           "Dashboard changed in another session. Reloaded version #{current_version}; review and try again."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to restore dashboard: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="ops-dashboard-directory-component"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_directory"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={%{}}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp reload_directory(socket) do
    %{current_scope: scope, current_mission: mission} = socket.assigns

    socket = OpsShellHook.refresh_dashboard_navigation(socket)

    archived =
      Cadence.Dashboards.list_archived_dashboard_summaries(
        scope.organization_id,
        mission.mission_id
      )

    all_summaries = socket.assigns.ops_dashboards ++ archived
    preferences = dashboard_preferences(scope, mission)
    preference_by_dashboard = Map.new(preferences, &{&1.dashboard_id, &1})
    tags = all_summaries |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

    entries =
      all_summaries
      |> filter_summaries(socket.assigns.directory_filters)
      |> sort_summaries(socket.assigns.directory_filters["sort"])
      |> Enum.map(
        &directory_entry(
          &1,
          preference_by_dashboard,
          mission.mission_id,
          socket.assigns.dashboard_author?
        )
      )

    socket
    |> assign(:archived_dashboards, archived)
    |> assign(:directory_tags, tags)
    |> assign(:directory_count, length(entries))
    |> assign(:directory_empty?, entries == [])
    |> assign(
      :dashboard_directory_page,
      directory_page_dto(mission.mission_id, socket.assigns.dashboard_author?, length(entries))
    )
    |> assign(
      :dashboard_directory_filters,
      directory_filters_dto(socket.assigns.directory_filters, tags)
    )
    |> stream(:dashboard_directory, entries, reset: true)
  end

  defp dashboard_preferences(scope, mission) do
    case current_user_id(scope) do
      user_id when is_binary(user_id) ->
        Cadence.Dashboards.list_dashboard_user_preferences(
          scope.organization_id,
          mission.mission_id,
          user_id
        )

      _missing_user ->
        []
    end
  end

  defp directory_entry(summary, preference_by_dashboard, mission_id, dashboard_author?) do
    preference = Map.get(preference_by_dashboard, summary.dashboard_id)
    starred? = not is_nil(preference) and preference.starred
    dashboard_id = summary.dashboard_id

    %{
      id: dashboard_id,
      dashboard_id: dashboard_id,
      name: summary.name,
      description: summary.description,
      tags: summary.tags,
      lifecycle: lifecycle_dto(summary.lifecycle_state),
      starred: starred?,
      open: dashboard_open_dto(mission_id, summary),
      star: dashboard_star_dto(summary, starred?),
      widget_version_label: "#{summary.widget_count} widgets · v#{summary.latest_version || 1}",
      restore: dashboard_restore_dto(summary)
    }
    |> maybe_put_clone(mission_id, summary, dashboard_author?)
  end

  defp directory_page_dto(mission_id, dashboard_author?, count) do
    %{
      id: "ops-dashboards-page",
      header: %{
        eyebrow: "Observe / Dashboards",
        heading: "Dashboard Directory",
        copy:
          "Find mission telemetry workspaces without crowding the navigation rail. Stars and recents are personal; dashboard definitions and tags remain mission shared.",
        count: %{id: "dashboard-directory-count", value: count, suffix: "matching"},
        author_actions: dashboard_author_actions_dto(mission_id, dashboard_author?)
      },
      list: %{
        id: "dashboard-directory-list",
        empty: %{
          id: "dashboard-directory-empty",
          icon: "hero-magnifying-glass",
          heading: "No matching dashboards",
          copy:
            "Change the search, tag, or lifecycle filter. The filter state is preserved in the URL."
        }
      }
    }
  end

  defp dashboard_author_actions_dto(_mission_id, false), do: []

  defp dashboard_author_actions_dto(mission_id, true) do
    [
      %{
        id: "dashboard-directory-new",
        label: "New Dashboard",
        icon: "hero-plus",
        icon_class: "h-4 w-4",
        href: ~p"/missions/#{mission_id}/ops/dashboards/new",
        class: "btn btn-primary btn-sm"
      },
      %{
        id: "dashboard-directory-import",
        label: "Import",
        icon: "hero-arrow-down-tray",
        icon_class: "h-4 w-4",
        href: ~p"/missions/#{mission_id}/ops/dashboards/new?mode=import",
        class: "btn btn-outline btn-sm"
      },
      %{
        id: "dashboard-directory-library",
        label: "Library",
        icon: "hero-squares-plus",
        icon_class: "h-4 w-4",
        href: ~p"/missions/#{mission_id}/ops/dashboards/library",
        class: "btn btn-ghost btn-sm"
      },
      %{
        id: "dashboard-directory-playlists",
        label: "Playlists",
        icon: "hero-play-circle",
        icon_class: "h-4 w-4",
        href: ~p"/missions/#{mission_id}/ops/dashboards/playlists",
        class: "btn btn-ghost btn-sm"
      }
    ]
  end

  defp directory_filters_dto(filters, tags) do
    %{
      id: "dashboard-directory-filter-form",
      values: filters,
      fields: %{
        query: %{
          id: "directory_query",
          name: "directory[query]",
          type: "search",
          label: "Search",
          placeholder: "Name, description, or tag",
          debounce_ms: 250
        },
        lifecycle:
          select_field_dto(
            "directory_lifecycle",
            "directory[lifecycle]",
            "Lifecycle",
            [{"Active", "active"}, {"Archived", "archived"}, {"All", "all"}]
          ),
        tag:
          select_field_dto(
            "directory_tag",
            "directory[tag]",
            "Tag",
            [{"All tags", "all"} | Enum.map(tags, &{&1, &1})]
          ),
        sort:
          select_field_dto(
            "directory_sort",
            "directory[sort]",
            "Sort",
            [
              {"Recently updated", "updated"},
              {"Name", "name"},
              {"Widget count", "widgets"}
            ]
          )
      }
    }
  end

  defp select_field_dto(id, name, label, options) do
    %{
      id: id,
      name: name,
      type: "select",
      label: label,
      options:
        Enum.map(options, fn {option_label, value} -> %{label: option_label, value: value} end)
    }
  end

  defp lifecycle_dto("active") do
    %{
      state: "active",
      class:
        "border px-1.5 py-0.5 font-mono text-[0.6rem] uppercase tracking-wider border-success/30 text-success"
    }
  end

  defp lifecycle_dto("archived") do
    %{
      state: "archived",
      class:
        "border px-1.5 py-0.5 font-mono text-[0.6rem] uppercase tracking-wider border-base-content/20 text-base-content/45"
    }
  end

  defp dashboard_open_dto(mission_id, %{lifecycle_state: "active"} = summary) do
    %{
      id: "dashboard-directory-open-#{summary.dashboard_id}",
      href: ~p"/missions/#{mission_id}/ops/dashboards/#{summary.dashboard_id}"
    }
  end

  defp dashboard_open_dto(_mission_id, _summary), do: nil

  defp dashboard_star_dto(summary, starred?) do
    archived? = summary.lifecycle_state == "archived"

    %{
      id: "dashboard-directory-star-#{summary.dashboard_id}",
      payload: %{
        "dashboard-id" => summary.dashboard_id,
        "starred" => to_string(not starred?)
      },
      aria_label: if(starred?, do: "Unstar #{summary.name}", else: "Star #{summary.name}"),
      aria_pressed: to_string(starred?),
      disabled: archived?,
      title: if(archived?, do: "Restore this dashboard before starring it", else: nil),
      icon: if(starred?, do: "hero-star-solid", else: "hero-star")
    }
  end

  defp dashboard_restore_dto(%{lifecycle_state: "archived"} = summary) do
    available? = dashboard_action_available?(summary, :restore)

    %{
      id: "restore-dashboard-#{summary.dashboard_id}",
      label: "Restore",
      icon: "hero-arrow-uturn-left",
      payload: %{
        "dashboard-id" => summary.dashboard_id,
        "expected-version" => to_string(summary.latest_version)
      },
      disabled: not available?,
      lifecycle_action: "restore",
      action_available: dashboard_action_available_text(summary, :restore)
    }
  end

  defp dashboard_restore_dto(_summary), do: nil

  defp maybe_put_clone(entry, mission_id, %{lifecycle_state: "active"} = summary, true) do
    Map.put(entry, :clone, %{
      id: "clone-dashboard-#{summary.dashboard_id}",
      label: "Clone",
      icon: "hero-document-duplicate",
      href:
        ~p"/missions/#{mission_id}/ops/dashboards/new?source_dashboard_id=#{summary.dashboard_id}"
    })
  end

  defp maybe_put_clone(entry, _mission_id, _summary, _dashboard_author?), do: entry

  defp filter_summaries(summaries, filters) do
    Enum.filter(summaries, fn summary ->
      lifecycle_matches?(summary, filters["lifecycle"]) and
        tag_matches?(summary, filters["tag"]) and
        query_matches?(summary, filters["query"])
    end)
  end

  defp lifecycle_matches?(_summary, "all"), do: true
  defp lifecycle_matches?(summary, lifecycle), do: summary.lifecycle_state == lifecycle

  defp tag_matches?(_summary, "all"), do: true
  defp tag_matches?(summary, tag), do: tag in summary.tags

  defp query_matches?(_summary, ""), do: true

  defp query_matches?(summary, query) do
    query = String.downcase(query)

    [summary.name, summary.description | summary.tags]
    |> Enum.any?(fn value ->
      is_binary(value) and String.contains?(String.downcase(value), query)
    end)
  end

  defp sort_summaries(summaries, "name") do
    Enum.sort_by(summaries, &String.downcase(&1.name))
  end

  defp sort_summaries(summaries, "widgets") do
    Enum.sort_by(summaries, &{-&1.widget_count, String.downcase(&1.name)})
  end

  defp sort_summaries(summaries, _updated) do
    Enum.sort(summaries, fn left, right ->
      left_updated_at = left.updated_at || ~U[1970-01-01 00:00:00Z]
      right_updated_at = right.updated_at || ~U[1970-01-01 00:00:00Z]

      case DateTime.compare(left_updated_at, right_updated_at) do
        :gt -> true
        :lt -> false
        :eq -> String.downcase(left.name) <= String.downcase(right.name)
      end
    end)
  end

  defp normalize_filters(params) do
    params = Map.take(params, @filter_keys)

    %{
      "query" => normalize_text(params["query"]),
      "lifecycle" => enum_value(params["lifecycle"], ~w(active archived all), "active"),
      "tag" => normalize_tag_filter(params["tag"]),
      "sort" => enum_value(params["sort"], ~w(updated name widgets), "updated")
    }
  end

  defp normalize_text(value) when is_binary(value), do: String.trim(value)
  defp normalize_text(_value), do: ""

  defp normalize_tag_filter(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "all"
      value -> value
    end
  end

  defp normalize_tag_filter(_value), do: "all"

  defp enum_value(value, allowed, default) do
    if value in allowed, do: value, else: default
  end

  defp directory_path(mission_id, filters) do
    query =
      filters
      |> Enum.reject(fn
        {"query", ""} -> true
        {"lifecycle", "active"} -> true
        {"tag", "all"} -> true
        {"sort", "updated"} -> true
        _filter -> false
      end)
      |> Map.new()

    if map_size(query) == 0 do
      ~p"/missions/#{mission_id}/ops/dashboards"
    else
      ~p"/missions/#{mission_id}/ops/dashboards?#{query}"
    end
  end

  defp validate_restore_available(socket, dashboard_id) when is_binary(dashboard_id) do
    case dashboard_summary(socket, dashboard_id) do
      nil ->
        {:error, :dashboard_not_found}

      summary ->
        if dashboard_action_available?(summary, :restore),
          do: {:ok, summary},
          else: {:error, :dashboard_restore_not_available}
    end
  end

  defp dashboard_summary(socket, dashboard_id) do
    socket.assigns.ops_dashboards
    |> Kernel.++(socket.assigns.archived_dashboards)
    |> Enum.find(&(&1.dashboard_id == dashboard_id))
  end

  defp restore_expected_version(%{"expected-version" => version}, _summary)
       when is_binary(version) do
    case Integer.parse(version) do
      {version, ""} when version > 0 -> {:ok, version}
      _invalid -> {:error, :invalid_dashboard_version}
    end
  end

  defp restore_expected_version(_params, summary), do: {:ok, summary.latest_version}

  defp dashboard_action_available?(summary, action) do
    summary
    |> Cadence.Dashboards.dashboard_lifecycle_status()
    |> Map.fetch!(availability_field(action))
  end

  defp availability_field(:archive), do: :archive_available?
  defp availability_field(:restore), do: :restore_available?

  defp dashboard_action_available_text(summary, action) do
    if dashboard_action_available?(summary, action), do: "true", else: "false"
  end

  defp current_user_id(scope) do
    case Map.get(scope, :user) do
      %{user_id: user_id} when is_binary(user_id) -> user_id
      _scope -> nil
    end
  end
end
