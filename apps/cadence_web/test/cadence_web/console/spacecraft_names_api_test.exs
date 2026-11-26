defmodule CadenceWeb.Console.SpacecraftNamesAPITest do
  @moduledoc "#847: spacecraft names and SCIDs, by ids or the whole mission in bounded pages."
  use CadenceWeb.ConnCase, async: true

  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  @fleet 1_000

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    other = TestFixtures.persist_mission!(org)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # 1,000 craft in one insert (the fixture writes one at a time); names out of id order, so the
    # sort is checked. One craft in another mission must never appear.
    rows =
      for n <- 1..@fleet do
        %{
          spacecraft_id: "sc-#{mission.mission_id}-#{n}",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          display_name:
            "EARENDIL-#{String.pad_leading(Integer.to_string(@fleet + 1 - n), 4, "0")}",
          scid: n,
          inserted_at: now
        }
      end

    {@fleet, _} = Repo.insert_all("mission_spacecraft", rows)
    TestFixtures.persist_spacecraft!(other, display_name: "ELSEWHERE-1")

    %{
      conn: TestFixtures.member_conn(user),
      base: "/api/v1/missions/#{mission.mission_id}/spacecraft/names",
      mission: mission
    }
  end

  defp names(conn, path), do: conn |> get(path) |> json_response(200)

  test "walks the whole mission in pages of at most 500, sorted by name, each craft once", c do
    first = names(c.conn, c.base)
    assert length(first["data"]["names"]) == 500
    assert cursor = first["meta"]["next_cursor"]

    second = names(c.conn, c.base <> "?cursor=" <> cursor)
    assert length(second["data"]["names"]) == 500
    assert second["meta"]["next_cursor"] == nil

    all = first["data"]["names"] ++ second["data"]["names"]
    assert length(Enum.uniq_by(all, & &1["id"])) == @fleet
    assert Enum.map(all, & &1["name"]) == Enum.sort(Enum.map(all, & &1["name"]))
    refute Enum.any?(all, &(&1["name"] == "ELSEWHERE-1"))
    assert %{"id" => _id, "name" => "EARENDIL-0001", "scid" => @fleet} = hd(all)
  end

  test "a smaller limit pages the same rows", c do
    page = names(c.conn, c.base <> "?limit=10")
    assert length(page["data"]["names"]) == 10
    assert is_binary(page["meta"]["next_cursor"])
  end

  test "answers only the given ids, at most 100", c do
    ids = "sc-#{c.mission.mission_id}-1,sc-#{c.mission.mission_id}-2"

    assert %{"data" => %{"names" => named}, "meta" => %{"next_cursor" => nil}} =
             names(c.conn, c.base <> "?ids=" <> ids)

    assert named |> Enum.map(& &1["scid"]) |> Enum.sort() == [1, 2]

    too_many = Enum.map_join(1..101, ",", &"sc-#{c.mission.mission_id}-#{&1}")

    assert %{"error" => %{"code" => "invalid_params"}} =
             c.conn |> get(c.base <> "?ids=" <> too_many) |> json_response(422)
  end

  test "refuses a cursor it didn't make", c do
    assert %{"error" => %{"code" => "invalid_params"}} =
             c.conn |> get(c.base <> "?cursor=not-a-cursor") |> json_response(422)
  end
end
