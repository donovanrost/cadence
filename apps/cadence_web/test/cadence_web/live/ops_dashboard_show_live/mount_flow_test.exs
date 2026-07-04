defmodule CadenceWeb.OpsDashboardShowLive.MountFlowTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 3]

  alias CadenceWeb.OpsDashboardShowLive.MountFlow
  alias Phoenix.LiveView.Socket

  test "mount_dashboard assigns loaded dashboard and activates runtime when connected" do
    document = %{dashboard_id: "dashboard-1"}

    assert {:ok, socket} =
             MountFlow.mount_dashboard(socket(), "dashboard-1", true,
               fetch_operator_document: fn scope, mission, dashboard_id ->
                 assert scope.organization_id == "org-1"
                 assert mission.mission_id == "mission-1"
                 assert dashboard_id == "dashboard-1"
                 {:ok, document, :published}
               end,
               assign_loaded_dashboard: fn socket, scope, mission, ^document, document_mode ->
                 assign(socket, :loaded_dashboard, {scope, mission, document_mode})
               end,
               activate_runtime: fn socket, scope, mission, ^document, connected?, runtime_opts ->
                 assign(socket, :runtime_activation, {scope, mission, connected?, runtime_opts})
               end,
               runtime_shell_opts: [sentinel: :ok],
               dashboard_list_path: fn _socket -> "/dashboards" end
             )

    assert socket.assigns.loaded_dashboard ==
             {%{organization_id: "org-1"}, %{mission_id: "mission-1"}, :published}

    assert socket.assigns.runtime_activation ==
             {%{organization_id: "org-1"}, %{mission_id: "mission-1"}, true, [sentinel: :ok]}
  end

  test "mount_dashboard passes disconnected state to runtime activation" do
    document = %{dashboard_id: "dashboard-1"}

    assert {:ok, socket} =
             MountFlow.mount_dashboard(socket(), "dashboard-1", false,
               fetch_operator_document: fn _scope, _mission, _dashboard_id ->
                 {:ok, document, :draft_preview}
               end,
               assign_loaded_dashboard: fn socket, _scope, _mission, ^document, document_mode ->
                 assign(socket, :document_mode, document_mode)
               end,
               activate_runtime: fn socket,
                                    _scope,
                                    _mission,
                                    ^document,
                                    connected?,
                                    _runtime_opts ->
                 assign(socket, :connected?, connected?)
               end,
               dashboard_list_path: fn _socket -> "/dashboards" end
             )

    assert socket.assigns.document_mode == :draft_preview
    assert socket.assigns.connected? == false
  end

  test "mount_dashboard redirects missing dashboards to the dashboard list" do
    assert {:ok, socket} =
             MountFlow.mount_dashboard(socket(), "missing-dashboard", true,
               fetch_operator_document: fn _scope, _mission, _dashboard_id ->
                 {:error, :dashboard_not_found}
               end,
               dashboard_list_path: fn _socket -> "/dashboards" end
             )

    assert socket.assigns.flash["error"] == "Dashboard not found."
    assert socket.redirected == {:live, :redirect, %{kind: :push, to: "/dashboards"}}
  end

  test "mount_dashboard redirects archived dashboards to the dashboard list" do
    assert {:ok, socket} =
             MountFlow.mount_dashboard(socket(), "archived-dashboard", true,
               fetch_operator_document: fn _scope, _mission, _dashboard_id ->
                 {:error, :dashboard_archived}
               end,
               dashboard_list_path: fn _socket -> "/dashboards" end
             )

    assert socket.assigns.flash["error"] == "Dashboard is archived."
    assert socket.redirected == {:live, :redirect, %{kind: :push, to: "/dashboards"}}
  end

  test "mount_dashboard reports unexpected load errors" do
    assert {:ok, socket} =
             MountFlow.mount_dashboard(socket(), "bad-dashboard", true,
               fetch_operator_document: fn _scope, _mission, _dashboard_id ->
                 {:error, {:storage_unavailable, :timeout}}
               end,
               dashboard_list_path: fn _socket -> "/dashboards" end
             )

    assert socket.assigns.flash["error"] ==
             "Failed to load dashboard: {:storage_unavailable, :timeout}"

    assert socket.redirected == {:live, :redirect, %{kind: :push, to: "/dashboards"}}
  end

  defp socket(assigns \\ %{}) do
    %Socket{
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            current_scope: %{organization_id: "org-1"},
            current_mission: %{mission_id: "mission-1"}
          },
          assigns
        )
    }
  end
end
