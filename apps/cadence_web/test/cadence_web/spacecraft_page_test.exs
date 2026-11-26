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

  # §11c B3-B5: the spacecraft directory, profiles and readiness pages redirect to the console's
  # Setup; the host keeps the spacecraft page itself (with identity and edit, L17/L22).
  test "the spacecraft page uses the exact pinned profile and satisfies its consumer contract",
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
      assert_page(
        view,
        "spacecraft_configuration",
        "spacecraft-configuration",
        "readConfiguration"
      )

    assert overview["document"]["protocol"]["downlink"] == to_string(profile.downlink_protocol)
    assert overview["scid"] == 0
    assert overview["active"] == nil
  end

  test "unbound and missing pinned profiles still load the spacecraft page",
       %{conn: conn, mission: mission, path: path} do
    unbound = TestFixtures.persist_spacecraft!(mission)

    missing =
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_type_id: "missing-profile",
        spacecraft_type_version: 1
      )

    for craft <- [unbound, missing] do
      base = path <> "/" <> craft.spacecraft_id
      {:ok, view, _} = live(conn, base)

      data =
        assert_page(
          view,
          "spacecraft_configuration",
          "spacecraft-configuration",
          "readConfiguration"
        )

      assert data["document"]["protocol"] == nil
      assert data["links"]["identity"] == base <> "/identity"
    end
  end

  test "spacecraft refresh rejects another mission's identity and revoked sessions",
       %{conn: conn, mission: mission, org: org, path: path} do
    craft = TestFixtures.persist_spacecraft!(mission)
    other_mission = TestFixtures.persist_mission!(org)
    other_craft = TestFixtures.persist_spacecraft!(other_mission)
    {:ok, view, _} = live(conn, path <> "/" <> craft.spacecraft_id)

    render_hook(view, "host:context", %{"path" => path <> "/" <> other_craft.spacecraft_id})
    assert_redirect(view, "/console")
    {:ok, view, _} = live(conn, path <> "/" <> craft.spacecraft_id)
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))

    render_hook(view, "host:context", %{"path" => path <> "/" <> craft.spacecraft_id})
    assert_redirect(view, "/console/sign-in")
  end

  defp snapshot(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["spacecraft_page"]

  defp assert_page(view, page, feature, validator) do
    assert has_element?(view, "#application-shell")

    assert %{"page" => ^page, "version" => 1, "status" => "ready", "data" => data} =
             snapshot(view)

    path =
      Path.join([
        @features,
        feature,
        if(feature == "spacecraft-configuration", do: "contracts.ts", else: "validation.ts")
      ])

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
