defmodule CadenceWeb.OpsDashboardActivityLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Dashboards.{Document, ValidationResult, Version}
  alias CadenceWeb.DashboardAuthorAuth

  alias CadenceWeb.OpsDashboardShowLive.{
    PublishReadinessModel
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

    {:ok, socket |> load_activity() |> assign(:federated_query_params, %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected = select_version(socket.assigns.dashboard_versions_list, params["version"])

    {:noreply,
     socket
     |> assign(:selected_publish_issue_id, params["selected_publish_issue"])
     |> assign(
       :federated_query_params,
       Map.take(params, ["dashboard_id", "version", "selected_publish_issue"])
     )
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
      <.vue
        id="ops-dashboard-activity-surface"
        v-component="FederatedFullPageSurface"
        application_key="ops_console"
        surface_id="dashboard_activity"
        host_scope="mission"
        mission_id={@current_mission.mission_id}
        query_params={@federated_query_params}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
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
      version_count = length(versions)
      activity_count = length(events)
      mission_id = mission.mission_id

      version_rows =
        Enum.map(versions, &dashboard_version_dto(&1, mission_id, dashboard_id))

      activity_rows =
        events
        |> Enum.reverse()
        |> Enum.map(&dashboard_activity_dto/1)

      socket
      |> assign(:page_title, "#{document.name} Activity")
      |> assign(:dashboard_document, document)
      |> assign(:dashboard_summary, summary)
      |> assign(:dashboard_versions_list, versions)
      |> assign(
        :dashboard_activity_page,
        dashboard_activity_page_dto(socket, document, version_count, activity_count)
      )
      |> assign_selected_version(selected)
      |> assign(:version_count, version_count)
      |> assign(:activity_count, activity_count)
      |> stream(:dashboard_versions, version_rows, reset: true)
      |> stream(:dashboard_activity, activity_rows, reset: true)
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
    |> assign(:selected_version_detail, selected_version_dto(socket, selected))
    |> assign(:dashboard_publish_readiness, readiness)
  end

  defp assign_selected_version(socket, nil) do
    socket
    |> assign(:selected_version, nil)
    |> assign(:selected_version_detail, nil)
    |> assign(:dashboard_publish_readiness, nil)
  end

  defp dashboard_activity_page_dto(socket, document, version_count, activity_count) do
    mission_id = socket.assigns.current_mission.mission_id
    dashboard_id = socket.assigns.dashboard_id

    %{
      id: "dashboard-activity-page",
      header: %{
        eyebrow: "Dashboard / Activity",
        heading: document.name,
        copy: "Immutable drafts, semantic change summaries, publication, and lifecycle audit."
      },
      actions: %{
        editor: %{
          id: "dashboard-activity-editor",
          label: "Edit Dashboard",
          href: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/edit",
          visible: socket.assigns.dashboard_author?
        },
        viewer: %{
          id: "dashboard-activity-viewer",
          label: "Viewer",
          href: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}"
        }
      },
      versions: %{
        label: "Versions",
        count_id: "dashboard-version-count",
        count: version_count,
        container_id: "dashboard-versions",
        empty_id: "dashboard-versions-empty",
        empty: "No saved versions."
      },
      activity: %{
        label: "Lifecycle audit",
        count_id: "dashboard-activity-count",
        count: activity_count,
        container_id: "dashboard-activity-events",
        empty_id: "dashboard-activity-empty",
        empty: "No lifecycle transitions recorded."
      }
    }
  end

  defp dashboard_version_dto(version, mission_id, dashboard_id) do
    %{
      id: version.dashboard_version_id,
      version: version.version,
      href:
        ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/activity?version=#{version.version}",
      snapshot_kind: to_string(version.snapshot_kind),
      change_summary: version.change_summary || "Dashboard created",
      saved: "#{format_time(version.inserted_at)} · #{version.created_by || "system"}"
    }
  end

  defp selected_version_dto(socket, selected) do
    summary = socket.assigns.dashboard_summary

    %{
      version: selected.version,
      change_summary: selected.change_summary || "Dashboard created",
      actions: %{
        visible: socket.assigns.dashboard_author?,
        restore: %{
          id: "dashboard-activity-restore",
          label: "Restore as Draft",
          disabled: selected.version == summary.latest_version,
          payload: %{version: Integer.to_string(selected.version)}
        },
        publish: %{
          id: "dashboard-activity-publish",
          label: "Publish Version",
          disabled: summary.lifecycle_state == "archived",
          payload: %{version: Integer.to_string(selected.version)}
        }
      },
      details: [
        %{label: "Widgets", value: length(selected.document.placements)},
        %{label: "Sections", value: length(selected.document.sections)},
        %{
          label: "Changed fields",
          value: changed_fields(selected, socket.assigns.dashboard_versions_list)
        }
      ]
    }
  end

  defp dashboard_activity_dto(event) do
    %{
      id: event.dashboard_lifecycle_event_id,
      dashboard_lifecycle_event_id: event.dashboard_lifecycle_event_id,
      event_type: to_string(event.event_type),
      label: event_label(event.event_type),
      occurred: "#{format_time(event.occurred_at)} · #{event.actor_id || "system"}",
      dashboard_version: event.dashboard_version
    }
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
