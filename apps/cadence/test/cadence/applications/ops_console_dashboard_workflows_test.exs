defmodule Cadence.Applications.OpsConsoleDashboardWorkflowsTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.DashboardWorkflows
  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Dashboards

  test "declares the exact dashboard host bindings" do
    assert DashboardWorkflows.bindings() == [
             {"dashboard_directory", "filter_dashboards"},
             {"dashboard_directory", "toggle_dashboard_star"},
             {"dashboard_directory", "restore_dashboard"},
             {"dashboard_new", "validate"},
             {"dashboard_new", "save"},
             {"dashboard_library", "stage-library-item"},
             {"dashboard_library", "create-library-item"},
             {"dashboard_library", "add-library-version"},
             {"dashboard_playlists", "create-playlist"},
             {"dashboard_playlist_present", "next-dashboard"},
             {"dashboard_settings", "validate-settings"},
             {"dashboard_settings", "save-settings"},
             {"dashboard_settings", "create-share"},
             {"dashboard_settings", "revoke-share"},
             {"dashboard_settings", "create-snapshot"},
             {"dashboard_settings", "archive-dashboard"}
           ]
  end

  test "executes a validated dashboard creation through the domain" do
    persist_mission_scope("org-dashboard-actions", "mission-dashboard-actions")

    request =
      request("save", %{"dashboard" => %{"name" => "Flight", "description" => "Telemetry"}})

    assert {:ok, %{"dashboardId" => dashboard_id, "dashboardVersion" => 1, "mode" => "new"}} =
             DashboardWorkflows.execute(
               scope("org-dashboard-actions", "mission-dashboard-actions"),
               HostContext.mission("mission-dashboard-actions"),
               "dashboard_new",
               request
             )

    assert {:ok, document} =
             Dashboards.fetch_document(
               "org-dashboard-actions",
               "mission-dashboard-actions",
               dashboard_id
             )

    assert document.name == "Flight"
    assert document.description == "Telemetry"
  end

  test "rejects a host context for another mission" do
    request = request("filter_dashboards", %{"directory" => %{}})

    assert {:error, :forbidden} =
             DashboardWorkflows.execute(
               scope("org-dashboard-actions", "mission-dashboard-actions"),
               HostContext.mission("mission-other"),
               "dashboard_directory",
               request
             )
  end

  test "rejects an unknown surface action" do
    request = request("filter_dashboards", %{"directory" => %{}})

    assert {:error, :unsupported_application_action} =
             DashboardWorkflows.execute(
               scope("org-dashboard-actions", "mission-dashboard-actions"),
               HostContext.mission("mission-dashboard-actions"),
               "dashboard_settings",
               request
             )
  end

  test "rejects malformed action input" do
    request = request("filter_dashboards", %{"directory" => %{"query" => self()}})

    assert {:error, %Cadence.Applications.ActionFailure{code: "invalid_action_input"}} =
             DashboardWorkflows.execute(
               scope("org-dashboard-actions", "mission-dashboard-actions"),
               HostContext.mission("mission-dashboard-actions"),
               "dashboard_directory",
               request
             )
  end

  defp request(action_id, params) do
    %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      action_id: action_id,
      params: params
    }
  end

  defp scope(organization_id, mission_id) do
    identity = %ServiceIdentity{
      service_identity_id: "service-dashboard-actions",
      organization_id: organization_id,
      mission_id: mission_id,
      display_name: "Dashboard actions",
      lifecycle_state: :active
    }

    %Scope{
      actor_kind: :service,
      organization_id: organization_id,
      mission_id: mission_id,
      service_identity: identity,
      capabilities: MapSet.new()
    }
  end
end
