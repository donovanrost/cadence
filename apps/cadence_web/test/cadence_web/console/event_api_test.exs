defmodule CadenceWeb.Console.EventAPITest do
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo
  alias Cadence.SpacecraftStore.SpacecraftRow
  alias CadenceWeb.ControlPlaneApiFixtures
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    ControlPlaneApiFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)

    %{
      user: user,
      org: org,
      mission: mission,
      base: "/api/console/v1/missions/#{mission.mission_id}"
    }
  end

  # seed_mission_read_models ingests and evaluates limits on 2023-11-15.
  defp window, do: "from=2023-11-15T00:00:00Z&to=2023-11-16T00:00:00Z"

  defp get_json(c, path), do: c.user |> TestFixtures.member_conn() |> get(c.base <> path)

  test "lists events in the window, newest first, with console kinds and severities", c do
    body = c |> get_json("/events?" <> window()) |> json_response(200)
    events = body["data"]["events"]

    assert events != []

    assert Enum.all?(
             events,
             &(&1["kind"] in ~w(limit flight_event contact command config operator data))
           )

    assert Enum.all?(events, &(&1["severity"] in ~w(critical caution nominal info)))

    times = Enum.map(events, & &1["at"])
    assert times == Enum.sort(times, :desc)
    assert Map.has_key?(body["meta"], "next_cursor")
  end

  test "pages with an opaque cursor and filters by kind", c do
    first = c |> get_json("/events?#{window()}&limit=1") |> json_response(200)
    assert [_one] = first["data"]["events"]

    if cursor = first["meta"]["next_cursor"] do
      second = c |> get_json("/events?#{window()}&limit=1&cursor=#{cursor}") |> json_response(200)
      refute second["data"]["events"] == first["data"]["events"]
    end

    only_config = c |> get_json("/events?#{window()}&kind=config") |> json_response(200)
    assert Enum.all?(only_config["data"]["events"], &(&1["kind"] == "config"))
  end

  test "density buckets severities across the window", c do
    data = c |> get_json("/events/density?#{window()}&bucket_s=3600") |> json_response(200)
    assert data["data"]["bucket_s"] == 3600

    for bucket <- data["data"]["buckets"] do
      assert Map.keys(bucket) |> Enum.sort() == ~w(caution critical info nominal t)
    end
  end

  test "rejects bad kinds, limits and cursors", c do
    assert json_response(get_json(c, "/events?kind=bogus"), 422)["error"]["details"]["kind"]
    assert json_response(get_json(c, "/events?limit=0"), 422)["error"]["details"]["limit"]
    assert json_response(get_json(c, "/events?cursor=%%%"), 422)["error"]["details"]["cursor"]

    assert json_response(get_json(c, "/events/density?bucket_s=5"), 422)["error"]["details"][
             "bucket_s"
           ]
  end

  test "filters by orbital plane (Timeline); an empty plane matches nothing", c do
    events =
      &(c |> get_json("/events?" <> &1) |> json_response(200) |> get_in(["data", "events"]))

    craft_id =
      window()
      |> events.()
      |> Enum.map(&get_in(&1, ["spacecraft", "id"]))
      |> Enum.find(&is_binary/1)

    # Put the seeded spacecraft in plane 3 (plane lives in spacecraft metadata).
    Repo.update_all(
      from(r in SpacecraftRow,
        where: r.spacecraft_id == ^craft_id and r.mission_id == ^c.mission.mission_id
      ),
      set: [metadata: JsonDocument.wrap_value(%{"plane" => 3})]
    )

    in_plane = events.("#{window()}&plane=3")
    assert in_plane != []
    assert Enum.all?(in_plane, &(get_in(&1, ["spacecraft", "id"]) == craft_id))

    assert events.("#{window()}&plane=7") == []

    assert %{"error" => %{"details" => %{"plane" => _}}} =
             c |> get_json("/events?#{window()}&plane=north") |> json_response(422)
  end

  test "a kind filter fills the page from older rows, not just the newest one read (fe-ops)", c do
    # The newest seeded event is a limit event; the contact is older. A page of one contact
    # used to come back empty because the kind filter ran after the newest row was taken.
    assert [%{"kind" => "contact"}] =
             c
             |> get_json("/events?#{window()}&kind=contact&limit=1")
             |> json_response(200)
             |> get_in(["data", "events"])
  end
end
