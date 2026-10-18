defmodule CadenceWeb.ApplicationManagementTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Cadence.Applications.ApplicationInstallations.InstallationRow
  alias Cadence.Repo
  alias Cadence.SpacecraftTypeStore
  alias CadenceWeb.TestFixtures

  @validator Path.expand(
               "../../../../frontend/apps/host/src/capability-management/features/application-installations/validation.ts",
               __DIR__
             )

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    {:ok, conn: TestFixtures.member_conn(user), org: org, mission: mission}
  end

  test "mission lifecycle snapshots satisfy the feature's actual runtime contract", %{
    conn: conn,
    mission: mission
  } do
    path = "/missions/#{mission.mission_id}/applications"
    {:ok, view, _} = live(conn, path)
    assert_contract(view, "mission")

    for {event, state} <- [
          {"install", "installed"},
          {"disable", "disabled"},
          {"uninstall", "uninstalled"}
        ] do
      render_hook(view, "host:manage", %{"path" => path, "event" => event, "key" => "limits"})
      data = assert_contract(view, "mission")
      applications = data["applications_component"]["props"]["applications"]

      assert Enum.find(applications, &(&1["application_key"] == "limits"))["lifecycle_state"] ==
               state
    end
  end

  test "missing and pinned profiles satisfy the real spacecraft contract and retain exact-version eligibility",
       %{conn: conn, org: org, mission: mission} do
    missing = TestFixtures.persist_spacecraft!(mission)
    {:ok, missing_view, _} = live(conn, path(mission, missing))
    missing_data = assert_contract(missing_view, "spacecraft")
    assert missing_data["profile"]["kind"] == "missing"

    assert missing_data["profile"]["action"]["path"] ==
             "/missions/#{mission.mission_id}/spacecraft/#{missing.spacecraft_id}/identity"

    profile = TestFixtures.persist_spacecraft_profile!(mission)

    assert {:ok, _newer} =
             SpacecraftTypeStore.persist_spacecraft_type(org.organization_id, %{
               profile
               | version: profile.version + 1,
                 applications: %{}
             })

    spacecraft =
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    {:ok, view, _} = live(conn, path(mission, spacecraft))
    data = assert_contract(view, "spacecraft")
    assert data["profile"]["version"] == profile.version
    assert Enum.any?(data["applications"], &(&1["application_key"] == "telemetry_decom"))

    for {event, state} <- [
          {"install", "installed"},
          {"disable", "disabled"},
          {"uninstall", "uninstalled"}
        ] do
      render_hook(view, "host:manage", %{
        "path" => path(mission, spacecraft),
        "event" => event,
        "key" => "telemetry_decom"
      })

      data = assert_contract(view, "spacecraft")

      assert Enum.find(data["applications"], &(&1["application_key"] == "telemetry_decom"))[
               "lifecycle_state"
             ] == state
    end

    refute Repo.get_by(InstallationRow,
             scope_id: missing.spacecraft_id,
             application_key: "telemetry_decom"
           )
  end

  defp path(mission, spacecraft),
    do: "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications"

  defp assert_contract(view, scope) do
    assert has_element?(view, "#application-shell")
    snapshot = LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]

    assert %{"version" => 1, "scope" => ^scope, "status" => "ready", "data" => data} =
             snapshot["application_management"]

    assert data == snapshot["presentation"]
    validator = if scope == "mission", do: "assertMission", else: "assertSpacecraft"

    node =
      System.find_executable("node") || flunk("Node is required for installation DTO validation")

    script =
      "import {#{validator}} from #{Jason.encode!(@validator)}; #{validator}(JSON.parse(process.argv[1]));"

    {output, status} =
      System.cmd(
        node,
        ["--no-warnings", "--input-type=module", "-e", script, Jason.encode!(data)],
        stderr_to_stdout: true
      )

    assert status == 0, output
    data
  end
end
