defmodule CadenceWeb.SpacecraftIdentityTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.Spacecraft.ActionProvider
  alias Cadence.Auth.Scope
  alias Cadence.Reads.Spacecraft.Profiles
  alias Cadence.Spacecraft.Identity
  alias Cadence.{SpacecraftStore, SpacecraftTypeStore}
  alias CadenceWeb.TestFixtures

  @validator Path.expand(
               "../../../../frontend/apps/host/src/mission-and-spacecraft/features/spacecraft-identity/validation.ts",
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
     path: "/missions/#{mission.mission_id}/spacecraft"}
  end

  # §11c B3: New spacecraft redirects to the console's Setup; identity and edit stay (L17).
  test "both identity routes produce valid host form contracts and scoped links", %{
    conn: conn,
    mission: mission,
    path: path
  } do
    profile = TestFixtures.persist_spacecraft_profile!(mission)

    craft =
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: 1
      )

    assert {:ok, _} =
             SpacecraftTypeStore.persist_spacecraft_type(mission.organization_id, %{
               profile
               | version: 2
             })

    {:ok, view, _} = live(conn, path <> "/" <> craft.spacecraft_id <> "/identity")

    for suffix <- ["/identity", "/edit"] do
      render_hook(view, "host:context", %{"path" => path <> "/" <> craft.spacecraft_id <> suffix})
      data = assert_form(view, "spacecraft_edit", "assertEditIdentityForm")
      assert data["form"]["profile_version"] == 1
      assert Enum.map(data["profile_options"]["options"], & &1["version"]) == [nil, 1, 2]
    end
  end

  test "reviewed framing links to Communications and private protocol records are not shared presets",
       %{conn: conn, mission: mission, path: path} do
    assert {:ok, profile} =
             SpacecraftTypeStore.persist_spacecraft_type(
               mission.organization_id,
               Cadence.SpacecraftType.new(%{
                 mission_id: mission.mission_id,
                 display_name: "Private communications",
                 downlink_protocol: :tm,
                 uplink_protocol: :tc,
                 metadata: %{"spacecraft_configuration_revision_id" => "configuration-one"}
               })
             )

    craft =
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: 1
      )

    assert {:ok, craft} =
             SpacecraftStore.update_spacecraft(mission.organization_id, %{
               craft
               | metadata: %{"spacecraft_configuration_revision_id" => "configuration-one"}
             })

    {:ok, view, _} = live(conn, path <> "/" <> craft.spacecraft_id <> "/identity")
    data = assert_form(view, "spacecraft_edit", "assertEditIdentityForm")

    assert data["form"]["configuration_href"] ==
             path <> "/" <> craft.spacecraft_id <> "?section=communications"

    assert data["form"]["fields"]["spacecraft_type_id"]["value"] == profile.spacecraft_type_id

    assert Profiles.directory(mission)["presentation"]["card"] == nil
  end

  test "identity edits preserve pins and permit explicit version changes or clearing", %{
    conn: conn,
    org: org,
    mission: mission,
    path: path
  } do
    profile = TestFixtures.persist_spacecraft_profile!(mission)

    craft =
      TestFixtures.persist_spacecraft!(mission,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: 1
      )

    assert {:ok, _} =
             SpacecraftTypeStore.persist_spacecraft_type(org.organization_id, %{
               profile
               | version: 2
             })

    edit_path = path <> "/" <> craft.spacecraft_id <> "/identity"
    {:ok, view, _} = live(conn, edit_path)

    act(
      view,
      edit_path,
      token(view),
      values(%{
        "display_name" => "Renamed",
        "spacecraft_type_id" => profile.spacecraft_type_id,
        "spacecraft_type_version" => 1
      })
    )

    assert {:ok, saved} =
             SpacecraftStore.fetch_spacecraft(
               org.organization_id,
               mission.mission_id,
               craft.spacecraft_id
             )

    assert saved.display_name == "Renamed"
    assert saved.spacecraft_type_version == 1
    render_hook(view, "host:context", %{"path" => path})
    render_hook(view, "host:context", %{"path" => edit_path})

    act(
      view,
      edit_path,
      token(view),
      values(%{
        "spacecraft_type_id" => profile.spacecraft_type_id,
        "spacecraft_type_version" => 2
      })
    )

    assert {:ok, upgraded} =
             SpacecraftStore.fetch_spacecraft(
               org.organization_id,
               mission.mission_id,
               craft.spacecraft_id
             )

    assert upgraded.spacecraft_type_version == 2
    render_hook(view, "host:context", %{"path" => path})
    render_hook(view, "host:context", %{"path" => edit_path})
    act(view, edit_path, token(view), values())

    assert {:ok, cleared} =
             SpacecraftStore.fetch_spacecraft(
               org.organization_id,
               mission.mission_id,
               craft.spacecraft_id
             )

    assert cleared.spacecraft_type_id == nil
    assert cleared.spacecraft_type_version == nil
  end

  test "invalid fields, unavailable versions and another mission's profile cannot be persisted",
       %{conn: conn, org: org, mission: mission, path: path} do
    other = TestFixtures.persist_mission!(org)
    foreign_profile = TestFixtures.persist_spacecraft_profile!(other)
    profile = TestFixtures.persist_spacecraft_profile!(mission)
    craft = TestFixtures.persist_spacecraft!(mission)
    identity = path <> "/" <> craft.spacecraft_id <> "/identity"
    {:ok, view, _} = live(conn, identity)

    for attrs <- [
          %{"display_name" => " "},
          %{"display_name" => %{"nested" => "value"}},
          %{"display_name" => String.duplicate("x", 256)},
          %{"scid" => "1024"},
          %{"scid" => "-1"},
          %{"scid" => "1.5"},
          %{
            "spacecraft_type_id" => foreign_profile.spacecraft_type_id,
            "spacecraft_type_version" => 1
          },
          %{"spacecraft_type_id" => profile.spacecraft_type_id, "spacecraft_type_version" => 999},
          %{"spacecraft_type_id" => profile.spacecraft_type_id, "spacecraft_type_version" => %{}},
          %{"spacecraft_type_id" => "", "spacecraft_type_version" => 1}
        ] do
      act(view, identity, token(view), values(attrs))
    end

    assert {:ok, ^craft} =
             SpacecraftStore.fetch_spacecraft(
               org.organization_id,
               mission.mission_id,
               craft.spacecraft_id
             )
  end

  test "page tokens rotate on navigation and stale actions cannot create or edit another resource",
       %{conn: conn, org: org, mission: mission, path: path} do
    first = TestFixtures.persist_spacecraft!(mission)
    second = TestFixtures.persist_spacecraft!(mission)
    first_path = path <> "/" <> first.spacecraft_id <> "/identity"
    second_path = path <> "/" <> second.spacecraft_id <> "/identity"
    {:ok, view, _} = live(conn, first_path)
    stale = token(view)
    render_hook(view, "host:context", %{"path" => second_path})
    act(view, first_path, stale, values())
    act(view, second_path, stale, values())
    render_hook(view, "host:context", %{"path" => first_path})
    refute token(view) == stale
    act(view, first_path, stale, values())

    assert {:ok, ^first} =
             SpacecraftStore.fetch_spacecraft(
               org.organization_id,
               mission.mission_id,
               first.spacecraft_id
             )

    assert {:ok, ^second} =
             SpacecraftStore.fetch_spacecraft(
               org.organization_id,
               mission.mission_id,
               second.spacecraft_id
             )
  end

  test "revoked sessions cannot submit identity changes", %{
    conn: conn,
    org: org,
    mission: mission,
    path: path
  } do
    craft = TestFixtures.persist_spacecraft!(mission)
    identity = path <> "/" <> craft.spacecraft_id <> "/identity"
    {:ok, view, _} = live(conn, identity)
    token = token(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))
    act(view, identity, token, values())
    assert_redirect(view, "/sign-in")

    assert {:ok, ^craft} =
             SpacecraftStore.fetch_spacecraft(
               org.organization_id,
               mission.mission_id,
               craft.spacecraft_id
             )
  end

  test "core and legacy action paths enforce bounds, uniqueness, scope and unchanged version pins",
       %{scope: scope, org: org, mission: mission} do
    profile = TestFixtures.persist_spacecraft_profile!(mission)

    craft =
      TestFixtures.persist_spacecraft!(mission,
        scid: 0,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: 1
      )

    assert {:ok, _} =
             SpacecraftTypeStore.persist_spacecraft_type(org.organization_id, %{
               profile
               | version: 2
             })

    input =
      values(%{"spacecraft_type_id" => profile.spacecraft_type_id, "scid" => "1023"})
      |> Map.update!("spacecraft", &Map.delete(&1, "spacecraft_type_version"))

    request = %ActionRequest{
      application_key: "spacecraft",
      application_version: 1,
      surface_id: "edit",
      surface_version: 1,
      action_id: "save",
      params: input
    }

    assert {:ok, _} =
             ActionProvider.execute(
               scope,
               HostContext.spacecraft(
                 mission.mission_id,
                 craft.spacecraft_id
               ),
               request
             )

    assert {:ok, saved} =
             SpacecraftStore.fetch_spacecraft(
               org.organization_id,
               mission.mission_id,
               craft.spacecraft_id
             )

    assert saved.spacecraft_type_version == 1
    assert saved.scid == 1023

    assert {:error, %{"scid" => [_ | _]}} =
             Identity.action(scope, mission.mission_id, nil, "save", values(%{"scid" => "1023"}))

    assert {:error, _} =
             Identity.action(
               %Scope{scope | mission_id: "different"},
               mission.mission_id,
               nil,
               "save",
               values()
             )

    assert length(SpacecraftStore.list_spacecraft(org.organization_id, mission.mission_id)) == 1
  end

  defp values(attrs \\ %{}),
    do: %{
      "spacecraft" =>
        Map.merge(
          %{
            "display_name" => "Vehicle",
            "scid" => "42",
            "spacecraft_type_id" => "",
            "spacecraft_type_version" => nil
          },
          attrs
        )
    }

  defp token(view), do: snapshot(view)["form_token"]

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

  defp assert_form(view, page, validator) do
    assert has_element?(view, "#application-shell")

    assert %{
             "page" => ^page,
             "status" => "ready",
             "version" => 1,
             "form_token" => token,
             "data" => data
           } = snapshot(view)

    assert is_binary(token)

    node =
      System.find_executable("node") || flunk("Node required for identity contract validation")

    script =
      "import {#{validator}} from #{Jason.encode!(@validator)}; #{validator}(JSON.parse(process.argv[1]));"

    {output, code} =
      System.cmd(
        node,
        ["--no-warnings", "--input-type=module", "-e", script, Jason.encode!(data)],
        stderr_to_stdout: true
      )

    assert code == 0, output
    data
  end
end
