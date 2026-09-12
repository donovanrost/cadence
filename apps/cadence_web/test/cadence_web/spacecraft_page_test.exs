defmodule CadenceWeb.SpacecraftPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.SpacecraftTypeStore
  alias CadenceWeb.TestFixtures

  @features Path.expand(
              "../../../../frontend/apps/host/src/mission-and-spacecraft/features",
              __DIR__
            )

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    {:ok,
     conn: TestFixtures.member_conn(user),
     org: org,
     mission: mission,
     path: "/missions/#{mission.mission_id}/spacecraft"}
  end

  test "empty directory and profiles load without frontend installations and satisfy consumer contracts",
       %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)

    data =
      assert_page(view, "spacecraft_list", "spacecraft-directory", "assertSpacecraftDirectory")

    assert data["presentation"]["roster"]["fleet_empty"]
    assert data["presentation"]["profiles"]["empty"]
    render_hook(view, "host:context", %{"path" => path <> "/profiles"})
    profiles = assert_page(view, "profile_list", "spacecraft-profiles", "assertProfileDirectory")
    assert profiles["presentation"]["card"] == nil
    assert profiles["presentation"]["empty_state"]["title"] == "No Spacecraft Profiles"
  end

  test "directory filters, sort, search, pagination and drift counts describe actual spacecraft",
       %{conn: conn, path: path, mission: mission} do
    profile = TestFixtures.persist_spacecraft_profile!(mission)

    for {name, scid} <- [{"Zulu", 42}, {"Alpha", 43}] do
      TestFixtures.persist_spacecraft!(mission,
        display_name: name,
        scid: scid,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: 1
      )
    end

    missing = TestFixtures.persist_spacecraft!(mission, display_name: "Unconfigured")

    assert {:ok, _} =
             SpacecraftTypeStore.persist_spacecraft_type(mission.organization_id, %{
               profile
               | version: 2
             })

    {:ok, view, _} = live(conn, path)

    data =
      assert_page(view, "spacecraft_list", "spacecraft-directory", "assertSpacecraftDirectory")

    assert Enum.find(
             data["presentation"]["summary_tiles"],
             &(&1["id"] == "spacecraft-tile-drift")
           )["value"] == 2

    for filter <- ["missing_scid", "missing_profile"] do
      render_hook(view, "host:context", %{"path" => path <> "?filter=" <> filter})
      roster = assert_directory(view)
      assert [%{"id" => id}] = roster["rows"]
      assert id == "spacecraft-#{missing.spacecraft_id}"
    end

    render_hook(view, "host:context", %{
      "path" => path <> "?filter=profile_drift&sort=display_name&dir=asc&pageSize=1&page=2"
    })

    roster = assert_directory(view)
    assert roster["total_count"] == 2
    assert roster["page_size"] == 1
    assert roster["page"] == 2
    assert roster["sort_by"] == "display_name"
    assert [%{"display_name" => "Zulu"}] = roster["rows"]

    render_hook(view, "host:context", %{
      "path" => path <> "?q=Alpha&sort=display_name&dir=desc&page=999"
    })

    roster = assert_directory(view)
    assert roster["search"] == "Alpha"
    assert roster["sort_dir"] == "desc"
    assert roster["page"] == 1
    assert [%{"display_name" => "Alpha"}] = roster["rows"]
    render_hook(view, "host:context", %{"path" => path <> "?q=nomatch"})
    roster = assert_directory(view)
    refute roster["fleet_empty"]
    assert roster["filtered_empty"]
  end

  test "profile detail supplies complete labels and immutable history, with path-owned identity",
       %{conn: conn, mission: mission, org: org, path: path} do
    profile = TestFixtures.persist_spacecraft_profile!(mission)

    assert {:ok, _} =
             SpacecraftTypeStore.persist_spacecraft_type(org.organization_id, %{
               profile
               | version: 2,
                 display_name: "Latest Profile"
             })

    other = TestFixtures.persist_mission!(org)
    other_profile = TestFixtures.persist_spacecraft_profile!(other)
    {:ok, view, _} = live(conn, path <> "/profiles")
    directory = assert_page(view, "profile_list", "spacecraft-profiles", "assertProfileDirectory")
    assert [%{"display_name" => "Latest Profile"}] = directory["presentation"]["card"]["rows"]
    detail_path = path <> "/profiles/" <> profile.spacecraft_type_id

    render_hook(view, "host:context", %{
      "path" =>
        detail_path <>
          "?mission_id=#{other.mission_id}&profile_id=#{other_profile.spacecraft_type_id}"
    })

    detail = assert_page(view, "profile_show", "spacecraft-profiles", "assertProfileDetail")
    assert detail["profile"]["profile_id"] == profile.spacecraft_type_id
    assert detail["profile"]["version"] == "v2"
    assert Enum.sort(Enum.map(detail["versions"], & &1["version"])) == ["v1", "v2"]
    assert length(detail["navigation"]["breadcrumbs"]) == 4

    render_hook(view, "host:context", %{
      "path" => path <> "/profiles/" <> other_profile.spacecraft_type_id
    })

    assert %{"status" => "unavailable"} = snapshot(view)
    refute Map.has_key?(snapshot(view), "data")
    assert has_element?(view, "#application-shell")
  end

  test "malformed queries are contained and a valid refresh recovers", %{conn: conn, path: path} do
    {:ok, view, _} = live(conn, path)

    for query <- ["q[nested]=bad", "filter=unknown", "q=" <> String.duplicate("x", 256)] do
      render_hook(view, "host:context", %{"path" => path <> "?" <> query})
      assert %{"status" => "unavailable"} = snapshot(view)
    end

    render_hook(view, "host:context", %{"path" => path <> "?pageSize=9999"})
    assert assert_directory(view)["page_size"] == 100
  end

  test "cross-organization reads and revoked-session refreshes cannot expose spacecraft", %{
    conn: conn,
    path: path
  } do
    other_org = TestFixtures.persist_org!()
    other_mission = TestFixtures.persist_mission!(other_org)
    TestFixtures.persist_spacecraft!(other_mission)
    {:ok, view, _} = live(conn, path)

    assert {:error, {:redirect, _}} =
             live(conn, "/missions/#{other_mission.mission_id}/spacecraft")

    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => path <> "/profiles"})
    assert_redirect(view, "/sign-in")
  end

  test "overview and readiness use the exact pinned profile and satisfy real consumer contracts",
       %{conn: conn, mission: mission, path: path} do
    profile =
      TestFixtures.persist_spacecraft_profile!(mission, display_name: "Pinned Flight Profile")

    craft =
      TestFixtures.persist_spacecraft!(mission,
        scid: 0,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: 1
      )

    assert {:ok, _} =
             SpacecraftTypeStore.persist_spacecraft_type(
               mission.organization_id,
               %{profile | version: 2, display_name: "Latest Profile", applications: %{}}
             )

    base = path <> "/" <> craft.spacecraft_id
    {:ok, view, _} = live(conn, base)

    overview =
      assert_page(view, "spacecraft_show", "spacecraft-overview", "assertSpacecraftOverview")

    assert overview["profile_binding"]["title"] == "Pinned Flight Profile"
    assert overview["profile_binding"]["version"] == "v1"
    assert overview["profile_binding"]["status"]["label"] == "Pinned"
    assert overview["overview"]["scid"]["value"] == "0"
    assert [%{"application_key" => "telemetry_decom"}] = overview["applications"]["rows"]
    render_hook(view, "host:context", %{"path" => base <> "/readiness"})

    data =
      assert_page(
        view,
        "spacecraft_readiness",
        "spacecraft-readiness",
        "assertSpacecraftReadiness"
      )

    assert data["context"] == %{
             "organizationId" => mission.organization_id,
             "missionId" => mission.mission_id,
             "spacecraftId" => craft.spacecraft_id
           }

    assert Enum.map(data["panels"], & &1["title"]) == ["Identity", "Profile", "Applications"]
    assert hd(data["panels"])["status"]["tone"] == "ready"

    assert Enum.map(data["contributions"], & &1["id"]) == [
             "comms.routing",
             "application.telemetry_decom"
           ]

    assert hd(data["contributions"])["status"]["tone"] == "info"
    refute data["page"]["status"]["tone"] == "ready"
    render_hook(view, "host:context", %{"path" => base})
    assert_page(view, "spacecraft_show", "spacecraft-overview", "assertSpacecraftOverview")
  end

  test "unbound and missing pinned profiles remain distinguishable without losing core pages",
       %{conn: conn, mission: mission, path: path} do
    unbound = TestFixtures.persist_spacecraft!(mission)

    missing =
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_type_id: "missing-profile",
        spacecraft_type_version: 1
      )

    for {craft, tone} <- [{unbound, "attention"}, {missing, "blocked"}] do
      base = path <> "/" <> craft.spacecraft_id
      {:ok, view, _} = live(conn, base)

      data =
        assert_page(view, "spacecraft_show", "spacecraft-overview", "assertSpacecraftOverview")

      assert data["profile_binding"]["status"]["tone"] == tone
      assert data["profile_binding"]["profile_action"]["href"] == base <> "/identity"
      render_hook(view, "host:context", %{"path" => base <> "/readiness"})

      readiness =
        assert_page(
          view,
          "spacecraft_readiness",
          "spacecraft-readiness",
          "assertSpacecraftReadiness"
        )

      profile_panel =
        Enum.find(readiness["panels"], &(&1["id"] == "spacecraft-readiness-profile"))

      assert profile_panel["status"]["tone"] == tone
    end
  end

  test "spacecraft refresh rejects another mission's identity and revoked sessions",
       %{conn: conn, mission: mission, org: org, path: path} do
    craft = TestFixtures.persist_spacecraft!(mission)
    other_mission = TestFixtures.persist_mission!(org)
    other_craft = TestFixtures.persist_spacecraft!(other_mission)
    {:ok, view, _} = live(conn, path <> "/" <> craft.spacecraft_id)

    render_hook(view, "host:context", %{
      "path" => path <> "/" <> other_craft.spacecraft_id <> "/readiness"
    })

    assert_redirect(view, path)
    {:ok, view, _} = live(conn, path <> "/" <> craft.spacecraft_id)
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))

    render_hook(view, "host:context", %{
      "path" => path <> "/" <> craft.spacecraft_id <> "/readiness"
    })

    assert_redirect(view, "/sign-in")
  end

  defp snapshot(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["spacecraft_page"]

  defp assert_directory(view),
    do:
      assert_page(view, "spacecraft_list", "spacecraft-directory", "assertSpacecraftDirectory")[
        "presentation"
      ]["roster"]

  defp assert_page(view, page, feature, validator) do
    assert has_element?(view, "#application-shell")

    assert %{"page" => ^page, "version" => 1, "status" => "ready", "data" => data} =
             snapshot(view)

    path = Path.join([@features, feature, "validation.ts"])

    node =
      System.find_executable("node") || flunk("Node is required for spacecraft DTO validation")

    script =
      """
      import * as consumer from #{Jason.encode!(path)};
      const data = JSON.parse(process.argv[1]);
      consumer.#{validator}(data);
      if (consumer.admitContributions &&
          consumer.admitContributions(data.contributions, data.context).some(item => item === null)) {
        throw new Error("Producer supplied an inadmissible readiness contribution");
      }
      """

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
