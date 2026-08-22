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
    {:ok,
     socket
     |> stream_configure(:dashboard_directory,
       dom_id: &"dashboard-directory-row-#{&1.summary.dashboard_id}"
     )
     |> assign(:page_title, "Dashboard Directory")
     |> assign(:ops_nav_item, :dashboards)
     |> assign(:archived_dashboards, [])
     |> assign(:directory_filters, @default_filters)
     |> assign(:directory_form, to_form(@default_filters, as: :directory))
     |> assign(:directory_tags, [])
     |> assign(:directory_count, 0)
     |> assign(:directory_empty?, true)
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
      <section id="ops-dashboards-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto flex max-w-[100rem] flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-primary/70">
                Observe / Dashboards
              </p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight">Dashboard Directory</h1>
              <p class="mt-2 max-w-3xl text-sm text-base-content/60">
                Find mission telemetry workspaces without crowding the navigation rail. Stars and
                recents are personal; dashboard definitions and tags remain mission shared.
              </p>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <span
                id="dashboard-directory-count"
                class="font-mono text-xs uppercase tracking-wider text-base-content/50"
              >
                {@directory_count} matching
              </span>
              <.link
                :if={@dashboard_author?}
                id="dashboard-directory-new"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/new"}
                class="btn btn-primary btn-sm"
              >
                <.icon name="hero-plus" class="h-4 w-4" /> New Dashboard
              </.link>
              <.link
                :if={@dashboard_author?}
                id="dashboard-directory-import"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/new?mode=import"}
                class="btn btn-outline btn-sm"
              >
                <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> Import
              </.link>
              <.link
                :if={@dashboard_author?}
                id="dashboard-directory-library"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/library"}
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-squares-plus" class="h-4 w-4" /> Library
              </.link>
              <.link
                :if={@dashboard_author?}
                id="dashboard-directory-playlists"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/playlists"}
                class="btn btn-ghost btn-sm"
              >
                <.icon name="hero-play-circle" class="h-4 w-4" /> Playlists
              </.link>
            </div>
          </div>
        </header>

        <div class="mx-auto max-w-[100rem] space-y-5 p-5 lg:p-7">
          <.form
            for={@directory_form}
            id="dashboard-directory-filter-form"
            phx-change="filter_dashboards"
            class="grid gap-3 border border-base-300 bg-base-200/25 p-3 md:grid-cols-4"
          >
            <.input
              field={@directory_form[:query]}
              type="search"
              label="Search"
              placeholder="Name, description, or tag"
              phx-debounce="250"
            />
            <.input
              field={@directory_form[:lifecycle]}
              type="select"
              label="Lifecycle"
              options={[
                {"Active", "active"},
                {"Archived", "archived"},
                {"All", "all"}
              ]}
            />
            <.input
              field={@directory_form[:tag]}
              type="select"
              label="Tag"
              options={[{"All tags", "all"} | Enum.map(@directory_tags, &{&1, &1})]}
            />
            <.input
              field={@directory_form[:sort]}
              type="select"
              label="Sort"
              options={[
                {"Recently updated", "updated"},
                {"Name", "name"},
                {"Widget count", "widgets"}
              ]}
            />
          </.form>

          <div id="dashboard-directory-list" phx-update="stream" class="grid gap-3 xl:grid-cols-2">
            <div
              id="dashboard-directory-empty"
              class="hidden only:flex min-h-56 flex-col items-center justify-center border border-dashed border-base-300 px-6 text-center xl:col-span-2"
            >
              <.icon name="hero-magnifying-glass" class="h-8 w-8 text-base-content/30" />
              <p class="mt-3 font-semibold">No matching dashboards</p>
              <p class="mt-1 text-sm text-base-content/55">
                Change the search, tag, or lifecycle filter. The filter state is preserved in the URL.
              </p>
            </div>

            <article
              :for={{id, entry} <- @streams.dashboard_directory}
              id={id}
              data-dashboard-directory-id={entry.summary.dashboard_id}
              data-dashboard-directory-lifecycle={entry.summary.lifecycle_state}
              data-dashboard-directory-starred={to_string(entry.starred?)}
              class="group border border-base-300 bg-base-100 p-4 transition-colors hover:border-primary/45"
            >
              <div class="flex items-start gap-3">
                <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <.link
                      :if={entry.summary.lifecycle_state == "active"}
                      id={"dashboard-directory-open-#{entry.summary.dashboard_id}"}
                      navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{entry.summary.dashboard_id}"}
                      class="truncate text-sm font-semibold text-primary hover:underline"
                    >
                      {entry.summary.name}
                    </.link>
                    <span
                      :if={entry.summary.lifecycle_state == "archived"}
                      class="truncate text-sm font-semibold text-base-content/70"
                    >
                      {entry.summary.name}
                    </span>
                    <span class={[
                      "border px-1.5 py-0.5 font-mono text-[0.6rem] uppercase tracking-wider",
                      entry.summary.lifecycle_state == "active" &&
                        "border-success/30 text-success",
                      entry.summary.lifecycle_state == "archived" &&
                        "border-base-content/20 text-base-content/45"
                    ]}>
                      {entry.summary.lifecycle_state}
                    </span>
                  </div>
                  <p
                    :if={entry.summary.description}
                    class="mt-1 line-clamp-2 text-sm text-base-content/60"
                  >
                    {entry.summary.description}
                  </p>
                  <div class="mt-3 flex flex-wrap items-center gap-1.5">
                    <span
                      :for={tag <- entry.summary.tags}
                      data-dashboard-directory-tag={tag}
                      class="border border-primary/20 bg-primary/5 px-1.5 py-0.5 font-mono text-[0.625rem] text-primary/80"
                    >
                      {tag}
                    </span>
                    <span
                      :if={entry.summary.tags == []}
                      class="font-mono text-[0.625rem] text-base-content/35"
                    >
                      untagged
                    </span>
                  </div>
                </div>

                <button
                  id={"dashboard-directory-star-#{entry.summary.dashboard_id}"}
                  type="button"
                  phx-click="toggle_dashboard_star"
                  phx-value-dashboard-id={entry.summary.dashboard_id}
                  phx-value-starred={to_string(not entry.starred?)}
                  aria-label={if entry.starred?, do: "Unstar #{entry.summary.name}", else: "Star #{entry.summary.name}"}
                  aria-pressed={to_string(entry.starred?)}
                  disabled={entry.summary.lifecycle_state == "archived"}
                  title={
                    if entry.summary.lifecycle_state == "archived",
                      do: "Restore this dashboard before starring it",
                      else: nil
                  }
                  class={[
                    "btn btn-ghost btn-xs shrink-0",
                    entry.starred? && "text-warning"
                  ]}
                >
                  <.icon
                    name={if entry.starred?, do: "hero-star-solid", else: "hero-star"}
                    class="h-4 w-4"
                  />
                </button>
              </div>

              <div class="mt-4 flex items-center justify-between gap-3 border-t border-base-300/60 pt-3">
                <p class="font-mono text-[0.65rem] uppercase tracking-wider text-base-content/45">
                  {entry.summary.widget_count} widgets · v{entry.summary.latest_version || 1}
                </p>
                <.link
                  :if={entry.summary.lifecycle_state == "active" and @dashboard_author?}
                  id={"clone-dashboard-#{entry.summary.dashboard_id}"}
                  navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/new?source_dashboard_id=#{entry.summary.dashboard_id}"}
                  class="btn btn-ghost btn-xs"
                >
                  <.icon name="hero-document-duplicate" class="h-3.5 w-3.5" /> Clone
                </.link>
                <.button
                  :if={entry.summary.lifecycle_state == "archived"}
                  id={"restore-dashboard-#{entry.summary.dashboard_id}"}
                  variant={:ghost}
                  size={:xs}
                  phx-click="restore_dashboard"
                  phx-value-dashboard-id={entry.summary.dashboard_id}
                  phx-value-expected-version={entry.summary.latest_version}
                  disabled={not dashboard_action_available?(entry.summary, :restore)}
                  data-dashboard-lifecycle-action="restore"
                  data-dashboard-action-available={
                    dashboard_action_available_text(entry.summary, :restore)
                  }
                >
                  <.icon name="hero-arrow-uturn-left" class="h-3.5 w-3.5" /> Restore
                </.button>
              </div>
            </article>
          </div>
        </div>
      </section>
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
      |> Enum.map(&directory_entry(&1, preference_by_dashboard))

    socket
    |> assign(:archived_dashboards, archived)
    |> assign(:directory_tags, tags)
    |> assign(:directory_count, length(entries))
    |> assign(:directory_empty?, entries == [])
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

  defp directory_entry(summary, preference_by_dashboard) do
    preference = Map.get(preference_by_dashboard, summary.dashboard_id)

    %{
      summary: summary,
      starred?: not is_nil(preference) and preference.starred,
      last_viewed_at: preference && preference.last_viewed_at
    }
  end

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
