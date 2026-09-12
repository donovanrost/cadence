defmodule CadenceWeb.HostContext do
  @moduledoc "Allowlisted transport data for the frontend application shell."

  def from_assigns(assigns) do
    scope =
      value(assigns, :current_scope, %{
        user: nil,
        organization: nil,
        capabilities: [],
        admin_mode?: false
      })

    %{
      version: 1,
      user: fields(scope.user, [:user_id, :display_name, :email]),
      organization: fields(scope.organization, [:organization_id, :display_name]),
      mission: fields(assigns[:current_mission], [:mission_id, :display_name, :slug]),
      spacecraft: fields(assigns[:current_spacecraft], [:spacecraft_id, :display_name]),
      capabilities: Enum.to_list(scope.capabilities),
      admin_mode: scope.admin_mode?,
      platform_admin: value(assigns, :user_menu_platform_admin?, false),
      organizations:
        Enum.map(value(assigns, :user_menu_memberships, []), fn %{organization: organization} ->
          fields(organization, [:organization_id, :display_name])
        end),
      csrf_token: Plug.CSRFProtection.get_csrf_token(),
      nav_context: assigns[:nav_context],
      nav_item: assigns[:nav_item],
      ops_nav_item: value(assigns, :ops_nav_item, :dashboards),
      unread_count: value(assigns, :unread_notifications_count, 0),
      notifications:
        Enum.map(value(assigns, :recent_notifications, []), fn notification ->
          notification
          |> fields([:notification_id, :title, :body, :read_at])
          |> Map.update!(:read_at, &timestamp/1)
        end),
      fleet_health: fleet_health(assigns[:fleet_health]),
      ops_context: ops_context(assigns[:ops_context]),
      dashboard_author: value(assigns, :dashboard_author?, false),
      active_dashboard_id: assigns[:active_dashboard_id],
      dashboard_navigation:
        Map.new(value(assigns, :ops_dashboard_navigation, %{starred: [], recent: []}), fn {key,
                                                                                           rows} ->
          {key, Enum.map(rows, &fields(&1, [:dashboard_id, :name]))}
        end),
      dock_surfaces:
        Enum.map(value(assigns, :ops_dock_surfaces, []), fn surface ->
          %{
            id: surface.id,
            application_key: surface.application_key,
            surface_id: surface.surface_definition.surface_id,
            label: surface.label
          }
        end)
    }
  end

  defp value(assigns, key, default), do: Map.get(assigns, key) || default

  defp fields(nil, _keys), do: nil
  defp fields(value, keys), do: Map.take(value, keys)
  defp timestamp(nil), do: nil
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value) <> "Z"

  defp fleet_health(value), do: fields(value, [:normalized_state_counts, :violating_points])
  defp ops_context(nil), do: nil

  defp ops_context(context) do
    %{
      pinned_focus: context.pinned_focus,
      modules:
        Enum.map(context.modules, fn section ->
          section
          |> Map.take([:key, :status, :count, :freshness])
          |> Map.put(:observed_at, timestamp(section.observed_at))
          |> Map.put(:data, section_data(section.key, section.data))
        end)
    }
  end

  defp section_data("fleet_health", data), do: fleet_health(data)

  defp section_data("alarms", data) do
    data
    |> Map.take([:active_count, :critical_count, :warning_count, :info_count])
    |> Map.put(:latest_transition_at, timestamp(data[:latest_transition_at]))
  end

  defp section_data("commands", data) do
    data
    |> Map.take([
      :queued_count,
      :release_pending_count,
      :in_flight_count,
      :failed_count,
      :indeterminate_count
    ])
    |> Map.put(
      :followed_command,
      fields(data[:followed_command], [:command_request_id, :command_name, :status, :target])
    )
  end

  defp section_data(_key, _data), do: nil
end
