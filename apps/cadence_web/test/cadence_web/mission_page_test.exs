defmodule CadenceWeb.MissionPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Cadence.Missions
  alias CadenceWeb.TestFixtures

  @features Path.expand(
              "../../../../frontend/apps/host/src/mission-and-spacecraft/features",
              __DIR__
            )

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    {:ok, conn: TestFixtures.member_conn(user), org: org}
  end

  test "core mission pages load without installations and satisfy the real feature contracts", %{
    conn: conn,
    org: org
  } do
    {:ok, view, _} = live(conn, "/missions")
    assert has_element?(view, "#application-shell")
    empty = assert_page(view, "mission_list", "mission-directory", "assertDirectory")
    assert empty["presentation"]["card"]["rows"] == []

    mission = TestFixtures.persist_mission!(org)
    identified = TestFixtures.persist_spacecraft!(mission, scid: 42)
    TestFixtures.persist_spacecraft!(mission)
    other_org = TestFixtures.persist_org!()
    other = TestFixtures.persist_mission!(other_org)

    render_hook(view, "host:context", %{"path" => "/missions"})
    directory = assert_page(view, "mission_list", "mission-directory", "assertDirectory")
    assert [%{"href" => href}] = directory["presentation"]["card"]["rows"]
    assert href == "/missions/#{mission.mission_id}"
    refute href == "/missions/#{other.mission_id}"

    render_hook(view, "host:context", %{"path" => "/missions/new"})
    assert_page(view, "mission_new", "mission-creation", "assertCreation")
    render_hook(view, "host:context", %{"path" => href <> "?mission_id=#{other.mission_id}"})
    overview = assert_page(view, "mission_overview", "mission-overview", "assertOverview")

    assert Enum.find(overview["overview"]["readiness_cards"], &(&1["title"] == "Need SCID"))[
             "value"
           ] == 1

    assert Enum.any?(
             overview["spacecraft_readiness"],
             &(&1["__dom_id"] == "spacecraft-readiness-#{identified.spacecraft_id}")
           )
  end

  test "creation derives organization and identity from authorized scope, not submitted fields",
       %{conn: conn, org: org} do
    {:ok, view, _} = live(conn, "/missions/new")

    mission_action(view, %{
      "path" => "/missions/new",
      "event" => "save",
      "input" => %{
        "organization_id" => "forged",
        "mission" => %{
          "display_name" => "Flight",
          "slug" => "flight",
          "mission_id" => "forged",
          "organization_id" => "forged"
        }
      }
    })

    assert [mission] = Missions.list_missions(org.organization_id)
    assert mission.display_name == "Flight"
    assert mission.organization_id == org.organization_id
    refute mission.mission_id == "forged"
  end

  test "a 500-spacecraft mission keeps fleet totals and a bounded overview", %{
    conn: conn,
    org: org
  } do
    mission = TestFixtures.persist_mission!(org)

    for index <- 1..500 do
      TestFixtures.persist_spacecraft!(mission,
        display_name: "EARENDIL-#{String.pad_leading(Integer.to_string(index), 3, "0")}",
        scid: if(index == 500, do: nil, else: index)
      )
    end

    {:ok, view, _} = live(conn, "/missions/#{mission.mission_id}")
    assert has_element?(view, "#application-shell")
    data = assert_page(view, "mission_overview", "mission-overview", "assertOverview")
    cards = Map.new(data["overview"]["readiness_cards"], &{&1["title"], &1["value"]})

    assert cards["Need SCID"] == 1
    assert cards["Ready Spacecraft"] == 0
    assert data["overview"]["setup"]["issue_count"] == 500
    assert length(data["spacecraft_readiness"]) == 25
    assert data["overview"]["setup"]["description"] =~ "25 of 500"
  end

  test "invalid fields, stale paths and unsupported events cannot create missions", %{
    conn: conn,
    org: org
  } do
    {:ok, view, _} = live(conn, "/missions/new")

    for values <- [
          %{"display_name" => " ", "slug" => "flight"},
          %{"display_name" => "Flight", "slug" => "UPPER CASE"},
          %{"display_name" => String.duplicate("x", 256), "slug" => "flight"},
          %{"display_name" => %{"nested" => "value"}, "slug" => "flight"}
        ] do
      mission_action(view, %{
        "path" => "/missions/new",
        "event" => "save",
        "input" => %{"mission" => values}
      })
    end

    assert Missions.list_missions(org.organization_id) == []
    render_hook(view, "host:context", %{"path" => "/missions"})

    for event <- ["save", "delete"] do
      mission_action(view, %{
        "path" => "/missions/new",
        "event" => event,
        "input" => %{"mission" => %{"display_name" => "Flight", "slug" => "flight"}}
      })
    end

    assert Missions.list_missions(org.organization_id) == []
  end

  test "revoked sessions cannot create missions", %{conn: conn, org: org} do
    {:ok, view, _} = live(conn, "/missions/new")
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))

    mission_action(view, %{
      "path" => "/missions/new",
      "event" => "save",
      "input" => %{"mission" => %{"display_name" => "Flight", "slug" => "flight"}}
    })

    assert_redirect(view, "/sign-in")
    assert Missions.list_missions(org.organization_id) == []
  end

  test "leaving and returning rotates creation identity and duplicate saves are rejected", %{
    conn: conn,
    org: org
  } do
    {:ok, view, _} = live(conn, "/missions/new")
    old = creation_token(view)
    render_hook(view, "host:context", %{"path" => "/missions"})
    render_hook(view, "host:context", %{"path" => "/missions/new"})
    current = creation_token(view)
    refute current == old

    payload = %{
      "path" => "/missions/new",
      "event" => "save",
      "input" => %{"mission" => %{"display_name" => "Flight", "slug" => "flight"}}
    }

    mission_action(view, Map.put(payload, "token", old))
    assert Missions.list_missions(org.organization_id) == []
    mission_action(view, Map.put(payload, "token", current))
    mission_action(view, Map.put(payload, "token", current))
    assert [_] = Missions.list_missions(org.organization_id)
  end

  defp creation_token(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["mission_page"][
        "creation_token"
      ]

  defp mission_action(view, payload),
    do:
      render_hook(
        view,
        "host:mission",
        Map.put_new(payload, "token", creation_token(view) || "stale")
      )

  defp assert_page(view, page, feature, validator) do
    assert %{"page" => ^page, "version" => 1, "status" => "ready", "data" => data} =
             LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["mission_page"]

    path = Path.join([@features, feature, "validation.ts"])
    node = System.find_executable("node") || flunk("Node is required for mission DTO validation")

    script =
      "import {#{validator}} from #{Jason.encode!(path)}; #{validator}(JSON.parse(process.argv[1]));"

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
