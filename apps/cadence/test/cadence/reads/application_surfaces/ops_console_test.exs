defmodule Cadence.Reads.ApplicationSurfaces.OpsConsoleTest do
  use ExUnit.Case, async: true

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole

  test "rejects malformed params before a mission read" do
    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               scope(),
               HostContext.mission("mission-1"),
               request("timeline", %{"unknown" => "value"})
             )
  end

  test "rejects a query param that attempts to change mission scope" do
    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               scope(),
               HostContext.mission("mission-1"),
               request("timeline", %{"mission_id" => "mission-2"})
             )
  end

  test "rejects a service scope bound to another mission" do
    other_mission_scope = %Scope{organization_id: "org-1", mission_id: "mission-2"}

    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               other_mission_scope,
               HostContext.mission("mission-1"),
               request("timeline", %{})
             )
  end

  test "requires subject ids for subject-scoped surfaces" do
    assert {:error, :unsupported_application_surface_query} =
             OpsConsole.load(
               scope(),
               HostContext.mission("mission-1"),
               request("dashboard_settings", %{})
             )
  end

  test "keeps every descriptor query pointed at this executable provider" do
    assert Enum.all?(
             Cadence.Applications.OpsConsole.surface_query_contributions(),
             fn contribution ->
               contribution.provider == OpsConsole
             end
           )
  end

  defp scope, do: %Scope{organization_id: "org-1"}

  defp request(surface_id, params) do
    %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: surface_id,
      surface_version: 1,
      query_id: "cadence.ops.#{surface_id}",
      query_version: 1,
      params: params
    }
  end
end
