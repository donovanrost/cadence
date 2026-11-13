defmodule CadenceWeb.MissionPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

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

  test "the mission overview loads without installations and satisfies its feature contract", %{
    conn: conn,
    org: org
  } do
    mission = TestFixtures.persist_mission!(org)
    identified = TestFixtures.persist_spacecraft!(mission, scid: 42)
    TestFixtures.persist_spacecraft!(mission)
    other_org = TestFixtures.persist_org!()
    other = TestFixtures.persist_mission!(other_org)

    {:ok, view, _} = live(conn, "/missions/#{mission.mission_id}?mission_id=#{other.mission_id}")
    assert has_element?(view, "#application-shell")
    overview = assert_page(view, "mission_overview", "mission-overview", "assertOverview")

    assert Enum.find(overview["overview"]["readiness_cards"], &(&1["title"] == "Need SCID"))[
             "value"
           ] == 1

    assert Enum.any?(
             overview["spacecraft_readiness"],
             &(&1["__dom_id"] == "spacecraft-readiness-#{identified.spacecraft_id}")
           )
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
