defmodule CadenceWeb.CatalogReimportRunningTest do
  @moduledoc """
  Host-action sweep row 7: importing a catalog file again is refused while an import of it is
  still running, on every path. The refusal lives in `Catalog.Reimport`, which the console, the
  mission catalog host action and the native catalog page all call.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext}
  alias Cadence.Applications.MissionCatalog.ActionProvider
  alias Cadence.Auth.Scope
  alias Cadence.Catalog.Reimport
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    running =
      mission
      |> TestFixtures.persist_catalog_database!()
      |> TestFixtures.start_catalog_revision_import!()

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization: org,
        organization_membership: membership
      })

    %{user: user, mission: mission, scope: scope, running: running}
  end

  test "the shared function refuses, naming the running import", c do
    run_id = c.running.import_run_id

    assert {:error, {:import_running, ^run_id}} =
             Reimport.execute(c.scope, c.mission.mission_id, c.running.artifact_id)
  end

  test "the console refuses with import_running", c do
    conn =
      c.user
      |> TestFixtures.member_conn()
      |> post(
        "/api/v1/missions/#{c.mission.mission_id}/catalog/artifacts/#{c.running.artifact_id}/reimport",
        %{}
      )

    assert %{"code" => "import_running", "details" => %{"import_run_id" => run_id}} =
             json_response(conn, conn.status)["error"]

    assert run_id == c.running.import_run_id
  end

  test "the host action refuses with an import_running failure", c do
    request = %ActionRequest{
      application_key: "mission_catalog",
      application_version: 1,
      surface_id: "catalog_artifact_show",
      surface_version: 1,
      action_id: "reimport",
      params: %{"artifact_id" => c.running.artifact_id}
    }

    assert {:error, %ActionFailure{code: "import_running"}} =
             ActionProvider.execute(c.scope, HostContext.mission(c.mission.mission_id), request)
  end
end
