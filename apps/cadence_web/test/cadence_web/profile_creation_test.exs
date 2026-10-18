defmodule CadenceWeb.ProfileCreationTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.Spacecraft.ActionProvider
  alias Cadence.Auth.Scope
  alias Cadence.Spacecraft.ProfileCreation
  alias Cadence.SpacecraftTypeStore
  alias CadenceWeb.TestFixtures

  @validator Path.expand(
               "../../../../frontend/apps/host/src/mission-and-spacecraft/features/profile-creation/validation.ts",
               __DIR__
             )

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    scope = %Scope{
      actor_kind: :user,
      user: user,
      organization_id: org.organization_id,
      mission_id: mission.mission_id,
      organization_membership: %{lifecycle_state: :active}
    }

    {:ok,
     conn: TestFixtures.member_conn(user),
     org: org,
     mission: mission,
     scope: scope,
     path: "/missions/#{mission.mission_id}/spacecraft/profiles"}
  end

  test "the core route produces the actual Vue contract and scoped cancellation", %{
    conn: conn,
    path: path
  } do
    {:ok, view, _} = live(conn, path <> "/new")
    assert has_element?(view, "#application-shell")

    assert %{
             "version" => 1,
             "page" => "profile_new",
             "status" => "ready",
             "form_token" => token,
             "data" => data
           } = snapshot(view)

    assert is_binary(token)
    assert data["form"]["actions"]["cancel"]["href"] == path

    node =
      System.find_executable("node") || flunk("Node is required for profile contract validation")

    script =
      "import {assertProfileForm} from #{Jason.encode!(@validator)}; assertProfileForm(JSON.parse(process.argv[1]));"

    {output, code} =
      System.cmd(
        node,
        ["--no-warnings", "--input-type=module", "-e", script, Jason.encode!(data)],
        stderr_to_stdout: true
      )

    assert code == 0, output
  end

  test "creation pins server identity and scope, normalizes declarations and consumes the token once",
       %{conn: conn, org: org, mission: mission, path: path} do
    {:ok, view, _} = live(conn, path <> "/new")
    token = snapshot(view)["form_token"]
    [application | _] = ProfileCreation.available_applications()

    input =
      values(%{
        "display_name" => " Profile ",
        "applications" => %{application.application_key => "1"},
        "spacecraft_type_id" => "forged",
        "organization_id" => "forged",
        "mission_id" => "forged",
        "version" => 99,
        "lifecycle_state" => "deleted",
        "metadata" => %{"forged" => true}
      })

    act(view, path <> "/new", token, input)
    act(view, path <> "/new", token, input)

    assert [profile] =
             SpacecraftTypeStore.list_spacecraft_types(org.organization_id, mission.mission_id)

    assert profile.display_name == "Profile"
    refute profile.spacecraft_type_id == "forged"
    assert profile.organization_id == org.organization_id
    assert profile.mission_id == mission.mission_id
    assert profile.version == 1
    assert profile.lifecycle_state == :active
    assert profile.packet_protocol == :space_packet
    assert profile.metadata == %{}
    assert profile.applications == %{application.application_key => %{}}
    assert profile.frame_parameters["frame_size"] == 1024
  end

  test "validation and saving share bounded input and application admission", %{
    scope: scope,
    mission: mission,
    org: org
  } do
    invalid = [
      %{"display_name" => " "},
      %{"display_name" => %{}},
      %{"display_name" => String.duplicate("a", 201)},
      %{"downlink_protocol" => "unknown"},
      %{"uplink_protocol" => "tm"},
      %{"frame_size" => "0"},
      %{"frame_size" => "2147483648"},
      %{"frame_size" => %{}},
      %{"secondary_header_length" => "-1"},
      %{"insert_zone_length" => "1.5"},
      %{"truncated_primary_header" => "yes"},
      %{"ocf_length" => "8"},
      %{"applications" => ["telemetry_decom"]},
      %{"applications" => %{"unknown" => "1"}}
    ]

    for attrs <- invalid, event <- ["validate", "save"] do
      assert {:error, errors} =
               ProfileCreation.action(scope, mission.mission_id, event, values(attrs))

      assert is_map(errors)
    end

    [application | _] = ProfileCreation.available_applications()

    assert {:error, %{"applications" => [_]}} =
             ProfileCreation.action(
               scope,
               mission.mission_id,
               "save",
               values(%{
                 "applications" => %{application.application_key => %{"forged_config" => true}}
               })
             )

    assert [] ==
             SpacecraftTypeStore.list_spacecraft_types(org.organization_id, mission.mission_id)
  end

  test "protocol selections preserve valid frame fields and legacy profile validation works", %{
    scope: scope,
    mission: mission
  } do
    for {downlink, uplink} <- [{"tm", "tc"}, {"aos", "tc"}, {"uslp", "uslp"}] do
      params =
        values(%{
          "downlink_protocol" => downlink,
          "uplink_protocol" => uplink,
          "secondary_header_length" => "4",
          "insert_zone_length" => "8",
          "truncated_primary_header" => "true",
          "ocf_length" => "4"
        })

      request = %ActionRequest{
        application_key: "spacecraft",
        application_version: 1,
        surface_id: "profile_new",
        surface_version: 1,
        action_id: "validate",
        params: params
      }

      assert {:ok, %{"valid" => true}} =
               ActionProvider.execute(scope, HostContext.mission(mission.mission_id), request)

      assert {:ok, %{"profileId" => id}} =
               ProfileCreation.action(scope, mission.mission_id, "save", params)

      assert {:ok, saved} =
               SpacecraftTypeStore.fetch_spacecraft_type(
                 scope.organization_id,
                 mission.mission_id,
                 id
               )

      assert Atom.to_string(saved.downlink_protocol) == downlink
      assert Atom.to_string(saved.uplink_protocol) == uplink

      assert saved.frame_parameters == %{
               "frame_size" => 1024,
               "secondary_header_length" => 4,
               "insert_zone_length" => 8,
               "truncated_primary_header" => true,
               "ocf_length" => 4
             }
    end
  end

  test "navigation and revoked authentication reject old creation actions", %{
    conn: conn,
    org: org,
    mission: mission,
    path: path
  } do
    {:ok, view, _} = live(conn, path <> "/new")
    token = snapshot(view)["form_token"]
    render_hook(view, "host:context", %{"path" => path})
    render_hook(view, "host:context", %{"path" => path <> "/new"})
    refute snapshot(view)["form_token"] == token
    act(view, path <> "/new", token, values())
    token = snapshot(view)["form_token"]
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
    act(view, path <> "/new", token, values())
    assert_redirect(view, "/sign-in")

    assert [] ==
             SpacecraftTypeStore.list_spacecraft_types(org.organization_id, mission.mission_id)
  end

  test "scope mismatch and malformed envelopes fail without creating profiles", %{
    scope: %Scope{} = scope,
    mission: mission,
    org: org
  } do
    assert {:error, _} =
             ProfileCreation.action(
               %Scope{scope | mission_id: "different"},
               mission.mission_id,
               "save",
               values()
             )

    assert {:error, _} =
             ProfileCreation.action(scope, mission.mission_id, "save", %{"spacecraft" => %{}})

    assert {:error, _} =
             ProfileCreation.action(scope, mission.mission_id, "save", %{"spacecraft_type" => []})

    assert [] ==
             SpacecraftTypeStore.list_spacecraft_types(org.organization_id, mission.mission_id)
  end

  defp snapshot(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["spacecraft_page"]

  defp act(view, path, token, input),
    do:
      render_hook(view, "host:spacecraft", %{
        "path" => path,
        "token" => token,
        "event" => "save",
        "input" => input
      })

  defp values(attrs \\ %{}),
    do: %{
      "spacecraft_type" =>
        Map.merge(
          %{
            "display_name" => "Profile",
            "downlink_protocol" => "tm",
            "uplink_protocol" => "tc",
            "frame_size" => "1024",
            "secondary_header_length" => "0",
            "insert_zone_length" => "0",
            "truncated_primary_header" => "false",
            "ocf_length" => "0",
            "applications" => %{}
          },
          attrs
        )
    }
end
