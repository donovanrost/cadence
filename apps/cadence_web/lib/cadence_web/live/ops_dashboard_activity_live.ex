defmodule CadenceWeb.OpsDashboardActivityLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.{Document, ValidationResult, Version}
  alias CadenceWeb.DashboardAuthorAuth

  alias CadenceWeb.OpsDashboardShowLive.{
    PublishReadinessModel,
    PublishValidationComponents
  }

  @impl true
  def mount(%{"dashboard_id" => dashboard_id}, _session, socket) do
    socket =
      socket
      |> stream_configure(:dashboard_versions, dom_id: &"dashboard-version-#{&1.version}")
      |> stream_configure(:dashboard_activity,
        dom_id: &"dashboard-activity-#{&1.dashboard_lifecycle_event_id}"
      )
      |> assign(:ops_nav_item, :dashboards)
      |> assign(:active_dashboard_id, dashboard_id)
      |> assign(:dashboard_id, dashboard_id)
      |> assign(:selected_version, nil)
      |> assign(:selected_publish_issue_id, nil)
      |> assign(:dashboard_publish_readiness, nil)
      |> assign(:version_count, 0)
      |> assign(:activity_count, 0)

    {:ok, load_activity(socket)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected = select_version(socket.assigns.dashboard_versions_list, params["version"])

    {:noreply,
     socket
     |> assign(:selected_publish_issue_id, params["selected_publish_issue"])
     |> assign_selected_version(selected)}
  end

  @impl true
  def handle_event("refresh_publish_readiness", _params, socket) do
    {:noreply, assign_selected_version(socket, socket.assigns.selected_version)}
  end

  @impl true
  def handle_event("publish_version", %{"version" => version}, socket) do
    with :ok <- authorize_mutation(socket),
         {:ok, parsed_version} <- parse_version(version),
         {:ok, published} <- publish_version(socket, parsed_version) do
      {:noreply,
       socket
       |> load_activity()
       |> put_flash(:info, "Dashboard version #{published.version} published.")}
    else
      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to publish dashboards.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to publish dashboard: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("restore_version", %{"version" => version}, socket) do
    with :ok <- authorize_mutation(socket),
         {:ok, parsed_version} <- parse_version(version),
         {:ok, restored} <- restore_version(socket, parsed_version) do
      {:noreply,
       socket
       |> load_activity()
       |> put_flash(:info, "Version #{parsed_version} restored as draft #{restored.version}.")}
    else
      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to restore versions.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to restore version: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="dashboard-activity-page" class="h-full overflow-y-auto bg-base-100">
        <header class="border-b border-primary/20 bg-base-200/70 px-5 py-5 hud-grid lg:px-7">
          <div class="mx-auto flex max-w-[100rem] items-end justify-between gap-4">
            <div>
              <p class="font-mono text-[0.65rem] uppercase tracking-[0.2em] text-primary/70">
                Dashboard / Activity
              </p>
              <h1 class="mt-1 text-2xl font-bold tracking-tight">{@dashboard_document.name}</h1>
              <p class="mt-2 text-sm text-base-content/60">
                Immutable drafts, semantic change summaries, publication, and lifecycle audit.
              </p>
            </div>
            <div class="flex gap-2">
              <.link
                id="dashboard-activity-editor"
                :if={@dashboard_author?}
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{@dashboard_id}/edit"}
                class="btn btn-primary btn-sm"
              >
                Edit Dashboard
              </.link>
              <.link
                id="dashboard-activity-viewer"
                navigate={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{@dashboard_id}"}
                class="btn btn-ghost btn-sm"
              >
                Viewer
              </.link>
            </div>
          </div>
        </header>

        <div class="mx-auto grid max-w-[100rem] gap-5 p-5 lg:grid-cols-[22rem_minmax(0,1fr)] lg:p-7">
          <nav class="space-y-3" aria-label="Dashboard versions">
            <div class="flex items-center justify-between">
              <p class="hud-label">Versions</p>
              <span id="dashboard-version-count" class="font-mono text-xs text-base-content/45">
                {@version_count}
              </span>
            </div>
            <div id="dashboard-versions" phx-update="stream" class="space-y-2">
              <p id="dashboard-versions-empty" class="hidden only:block border border-dashed border-base-300 p-4 text-sm text-base-content/55">
                No saved versions.
              </p>
              <.link
                :for={{id, version} <- @streams.dashboard_versions}
                id={id}
                patch={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{@dashboard_id}/activity?version=#{version.version}"}
                data-dashboard-version={version.version}
                class={[
                  "block border p-3 transition-colors",
                  @selected_version && @selected_version.version == version.version &&
                    "border-primary bg-primary/5",
                  (is_nil(@selected_version) or @selected_version.version != version.version) &&
                    "border-base-300 hover:border-primary/40"
                ]}
              >
                <div class="flex items-center justify-between gap-2">
                  <span class="font-mono text-xs font-semibold">v{version.version}</span>
                  <span class="font-mono text-[0.6rem] uppercase text-base-content/45">
                    {version.snapshot_kind}
                  </span>
                </div>
                <p class="mt-2 text-sm">{version.change_summary || "Dashboard created"}</p>
                <p class="mt-1 text-[0.65rem] text-base-content/45">
                  {format_time(version.inserted_at)} · {version.created_by || "system"}
                </p>
              </.link>
            </div>
          </nav>

          <div class="min-w-0 space-y-5">
            <section
              id="dashboard-version-detail"
              class="border border-base-300 bg-base-200/20 p-5"
              data-selected-version={@selected_version && @selected_version.version}
            >
              <%= if @selected_version do %>
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p class="hud-label">Selected version</p>
                    <h2 class="mt-1 text-xl font-semibold">Version {@selected_version.version}</h2>
                    <p class="mt-1 text-sm text-base-content/60">
                      {@selected_version.change_summary || "Dashboard created"}
                    </p>
                  </div>
                  <div :if={@dashboard_author?} class="flex gap-2">
                    <.button
                      id="dashboard-activity-restore"
                      variant={:ghost}
                      size={:sm}
                      phx-click="restore_version"
                      phx-value-version={@selected_version.version}
                      disabled={@selected_version.version == @dashboard_summary.latest_version}
                    >
                      Restore as Draft
                    </.button>
                    <.button
                      id="dashboard-activity-publish"
                      variant={:primary}
                      size={:sm}
                      phx-click="publish_version"
                      phx-value-version={@selected_version.version}
                      disabled={@dashboard_summary.lifecycle_state == "archived"}
                    >
                      Publish Version
                    </.button>
                  </div>
                </div>
                <dl class="mt-5 grid gap-3 border-t border-base-300 pt-4 sm:grid-cols-3">
                  <.detail label="Widgets" value={length(@selected_version.document.placements)} />
                  <.detail label="Sections" value={length(@selected_version.document.sections)} />
                  <.detail label="Changed fields" value={changed_fields(@selected_version, @dashboard_versions_list)} />
                </dl>
                <div class="mt-5 border-t border-base-300 pt-4">
                  <PublishValidationComponents.publish_validation
                    publish_readiness={@dashboard_publish_readiness}
                    selected_publish_issue_id={@selected_publish_issue_id}
                    dashboard_document={@selected_version.document}
                    dashboard_current_path={~p"/missions/#{@current_mission.mission_id}/ops/dashboards/#{@dashboard_id}/activity?version=#{@selected_version.version}"}
                  />
                </div>
              <% else %>
                <p class="text-sm text-base-content/55">Select a version to inspect its saved state.</p>
              <% end %>
            </section>

            <section class="border border-base-300 bg-base-200/20 p-5">
              <div class="flex items-center justify-between">
                <p class="hud-label">Lifecycle audit</p>
                <span id="dashboard-activity-count" class="font-mono text-xs text-base-content/45">
                  {@activity_count}
                </span>
              </div>
              <div id="dashboard-activity-events" phx-update="stream" class="mt-3 divide-y divide-base-300/70">
                <p id="dashboard-activity-empty" class="hidden only:block py-4 text-sm text-base-content/55">
                  No lifecycle transitions recorded.
                </p>
                <article
                  :for={{id, event} <- @streams.dashboard_activity}
                  id={id}
                  class="flex items-start gap-3 py-3"
                  data-dashboard-activity-type={event.event_type}
                >
                  <span class="mt-1 h-2 w-2 rounded-full bg-primary"></span>
                  <div class="min-w-0 flex-1">
                    <p class="text-sm font-medium">{event_label(event.event_type)}</p>
                    <p class="mt-0.5 font-mono text-[0.65rem] text-base-content/45">
                      {format_time(event.occurred_at)} · {event.actor_id || "system"}
                    </p>
                  </div>
                  <span :if={event.dashboard_version} class="font-mono text-xs text-base-content/50">
                    v{event.dashboard_version}
                  </span>
                </article>
              </div>
            </section>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp detail(assigns) do
    ~H"""
    <div>
      <dt class="hud-label">{@label}</dt>
      <dd class="mt-1 font-mono text-sm">{@value}</dd>
    </div>
    """
  end

  defp load_activity(socket) do
    %{current_scope: scope, current_mission: mission, dashboard_id: dashboard_id} = socket.assigns

    with {:ok, %Document{} = document} <-
           Cadence.Dashboards.fetch_document(
             scope.organization_id,
             mission.mission_id,
             dashboard_id
           ),
         summary when not is_nil(summary) <- dashboard_summary(scope, mission, dashboard_id) do
      versions =
        Cadence.Dashboards.list_versions(scope.organization_id, mission.mission_id, dashboard_id)

      events =
        Cadence.Dashboards.list_lifecycle_events(
          scope.organization_id,
          mission.mission_id,
          dashboard_id
        )

      selected = socket.assigns.selected_version || List.last(versions)

      socket
      |> assign(:page_title, "#{document.name} Activity")
      |> assign(:dashboard_document, document)
      |> assign(:dashboard_summary, summary)
      |> assign(:dashboard_versions_list, versions)
      |> assign_selected_version(selected)
      |> assign(:version_count, length(versions))
      |> assign(:activity_count, length(events))
      |> stream(:dashboard_versions, versions, reset: true)
      |> stream(:dashboard_activity, Enum.reverse(events), reset: true)
    else
      _missing ->
        socket
        |> put_flash(:error, "Dashboard activity is unavailable.")
        |> push_navigate(to: ~p"/missions/#{mission.mission_id}/ops/dashboards")
    end
  end

  defp dashboard_summary(scope, mission, dashboard_id) do
    (Cadence.Dashboards.list_dashboard_summaries(scope.organization_id, mission.mission_id) ++
       Cadence.Dashboards.list_archived_dashboard_summaries(
         scope.organization_id,
         mission.mission_id
       ))
    |> Enum.find(&(&1.dashboard_id == dashboard_id))
  end

  defp select_version(versions, nil), do: List.last(versions)

  defp select_version(versions, version) do
    case parse_version(version) do
      {:ok, parsed} -> Enum.find(versions, &(&1.version == parsed)) || List.last(versions)
      {:error, :invalid_version} -> List.last(versions)
    end
  end

  defp publish_version(socket, version) do
    %{current_scope: scope, current_mission: mission, dashboard_summary: summary} = socket.assigns

    with %Version{} = selected <-
           Enum.find(socket.assigns.dashboard_versions_list, &(&1.version == version)),
         document <- validation_document(socket, selected),
         %ValidationResult{valid?: true} <-
           Cadence.Dashboards.validate_publish_readiness(
             scope.organization_id,
             mission.mission_id,
             document
           ) do
      Cadence.Dashboards.publish_document(
        scope.organization_id,
        mission.mission_id,
        socket.assigns.dashboard_id,
        version,
        expected_version: summary.latest_version,
        published_by: current_user_id(scope)
      )
    else
      %ValidationResult{} = validation ->
        {:error, {:dashboard_publish_validation_failed, validation}}

      nil ->
        {:error, :dashboard_version_not_found}
    end
  end

  defp assign_selected_version(socket, %Version{} = selected) do
    %{current_scope: scope, current_mission: mission} = socket.assigns
    document = validation_document(socket, selected)

    readiness =
      scope.organization_id
      |> Cadence.Dashboards.validate_publish_readiness(mission.mission_id, document)
      |> PublishReadinessModel.build()

    socket
    |> assign(:selected_version, selected)
    |> assign(:dashboard_publish_readiness, readiness)
  end

  defp assign_selected_version(socket, nil) do
    socket
    |> assign(:selected_version, nil)
    |> assign(:dashboard_publish_readiness, nil)
  end

  defp validation_document(
         %{
           assigns: %{dashboard_summary: %{latest_version: version}, dashboard_document: document}
         },
         %Version{version: version}
       ),
       do: document

  defp validation_document(_socket, %Version{document: document}), do: document

  defp restore_version(socket, version) do
    %{current_scope: scope, current_mission: mission, dashboard_summary: summary} = socket.assigns

    Cadence.Dashboards.revert_document(
      scope.organization_id,
      mission.mission_id,
      socket.assigns.dashboard_id,
      version,
      expected_version: summary.latest_version,
      created_by: current_user_id(scope)
    )
  end

  defp authorize_mutation(socket) do
    if DashboardAuthorAuth.authorized?(
         socket.assigns.current_scope,
         socket.assigns.current_mission.mission_id
       ),
       do: :ok,
       else: {:error, :forbidden}
  end

  defp parse_version(version) when is_integer(version) and version > 0, do: {:ok, version}

  defp parse_version(version) when is_binary(version) do
    case Integer.parse(version) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _invalid -> {:error, :invalid_version}
    end
  end

  defp parse_version(_version), do: {:error, :invalid_version}

  defp changed_fields(%Version{version: 1}, _versions), do: "initial document"

  defp changed_fields(%Version{} = version, versions) do
    previous = Enum.find(versions, &(&1.version == version.version - 1))

    case previous do
      %Version{} ->
        current_map = Document.to_map(version.document)
        previous_map = Document.to_map(previous.document)

        current_map
        |> Map.keys()
        |> Enum.filter(&(Map.get(current_map, &1) != Map.get(previous_map, &1)))
        |> Enum.map_join(", ", &to_string/1)
        |> case do
          "" -> "none"
          fields -> fields
        end

      nil ->
        "baseline unavailable"
    end
  end

  defp event_label(event_type) do
    event_type
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_time(%DateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")
  defp format_time(_value), do: "time unavailable"

  defp current_user_id(%{user: %{user_id: user_id}}) when is_binary(user_id), do: user_id
  defp current_user_id(_scope), do: nil
end
