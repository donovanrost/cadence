defmodule CadenceWeb.Console.EventAPITest do
  use CadenceWeb.ConnCase, async: false

  import Ecto.Query

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
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

  test "rows carry their record (A8a); one event reads back by id (A8b); unknown is 404", c do
    events =
      c |> get_json("/events?" <> window()) |> json_response(200) |> get_in(["data", "events"])

    assert Enum.all?(events, fn event ->
             Map.keys(event["record"]) |> Enum.sort() ==
               ~w(activation_id capability_instance_id correlation_key path_id realized_contact_id
                  scheduled_contact_id source_endpoint_ref source_record status)
           end)

    for event <- Enum.take(events, 3) do
      shown =
        c
        |> get_json("/events/" <> URI.encode_www_form(event["id"]))
        |> json_response(200)
        |> get_in(["data", "event"])

      assert Map.take(shown, ~w(id at kind raw_kind severity text record)) ==
               Map.take(event, ~w(id at kind raw_kind severity text record))
    end

    body = c |> get_json("/events/mission_event:nope") |> json_response(404)
    assert body["error"]["code"] == "event_not_found"
  end

  test "raw_kind filters the page and the bar; the picker counts raw kinds (A9b)", c do
    all =
      c |> get_json("/events?" <> window()) |> json_response(200) |> get_in(["data", "events"])

    [%{"raw_kind" => raw} | _] = all
    expected = Enum.count(all, &(&1["raw_kind"] == raw))

    exact =
      c
      |> get_json("/events?#{window()}&raw_kind=#{raw}")
      |> json_response(200)
      |> get_in(["data", "events"])

    assert length(exact) == expected and Enum.all?(exact, &(&1["raw_kind"] == raw))

    prefix = String.slice(raw, 0, 3) <> "*"

    by_prefix =
      c
      |> get_json("/events?#{window()}&raw_kind=#{prefix}")
      |> json_response(200)
      |> get_in(["data", "events"])

    assert Enum.all?(by_prefix, &String.starts_with?(&1["raw_kind"], String.slice(raw, 0, 3)))
    assert length(by_prefix) >= expected

    bar =
      c
      |> get_json("/events/density?#{window()}&raw_kind=#{raw}")
      |> json_response(200)
      |> get_in(["data", "buckets"])

    assert bar
           |> Enum.map(&(&1["critical"] + &1["caution"] + &1["nominal"] + &1["info"]))
           |> Enum.sum() ==
             expected

    picker =
      c
      |> get_json("/events/raw-kinds?" <> window())
      |> json_response(200)
      |> get_in(["data", "raw_kinds"])

    assert %{"count" => count, "kind" => kind} = Enum.find(picker, &(&1["raw_kind"] == raw))

    assert count == expected and
             kind in ~w(limit flight_event contact command config operator data)

    for bad <- ["Bad-Kind", "a*b", Enum.map_join(1..21, ",", &"k#{&1}")] do
      body =
        c
        |> get_json("/events?#{window()}&raw_kind=" <> URI.encode_www_form(bad))
        |> json_response(422)

      assert %{"raw_kind" => _} = body["error"]["details"]
    end
  end

  test "severity_at_least keeps caution and above on the page and the bar (A9a)", c do
    all =
      c |> get_json("/events?" <> window()) |> json_response(200) |> get_in(["data", "events"])

    serious = Enum.filter(all, &(&1["severity"] in ~w(caution critical)))
    assert serious != [], "the seeded limit evaluation raises a caution"

    page =
      c
      |> get_json("/events?#{window()}&severity_at_least=caution")
      |> json_response(200)
      |> get_in(["data", "events"])

    assert Enum.map(page, & &1["id"]) == Enum.map(serious, & &1["id"])

    critical =
      c
      |> get_json("/events?#{window()}&severity_at_least=critical")
      |> json_response(200)
      |> get_in(["data", "events"])

    assert Enum.all?(critical, &(&1["severity"] == "critical"))

    bar =
      c
      |> get_json("/events/density?#{window()}&severity_at_least=caution")
      |> json_response(200)
      |> get_in(["data", "buckets"])

    assert Enum.sum(Enum.map(bar, &(&1["nominal"] + &1["info"]))) == 0
    assert Enum.sum(Enum.map(bar, &(&1["caution"] + &1["critical"]))) == length(serious)

    body = c |> get_json("/events?#{window()}&severity_at_least=warning") |> json_response(422)
    assert %{"severity_at_least" => _} = body["error"]["details"]
  end

  test "ground health is data and limit-definition lifecycle is config, never flight_event", c do
    now = DateTime.utc_now()

    recent =
      "from=#{DateTime.add(now, -3_600)}&to=#{DateTime.add(now, 60)}"
      |> String.replace("+", "%2B")

    events =
      Enum.flat_map([window(), recent], fn range ->
        c |> get_json("/events?" <> range) |> json_response(200) |> get_in(["data", "events"])
      end)

    refute Enum.any?(events, &(&1["kind"] == "flight_event"))

    for %{"raw_kind" => "limit_definition_" <> _} = event <- events,
        do: assert(event["kind"] == "config")

    for %{"raw_kind" => "source_health_recovered"} = event <- events,
        do: assert(event["severity"] == "nominal")

    assert Enum.any?(events, &match?(%{"raw_kind" => "limit_definition_" <> _}, &1))
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

  test "the default kinds skip housekeeping rows in SQL; kind=data still returns them", c do
    # domain 11-15 21:08Z: per-write watermark rows (~92% of dev) timed the Timeline out.
    now = DateTime.utc_now()

    range =
      "from=#{DateTime.add(now, -86_400 * 3_650)}&to=#{DateTime.add(now, 60)}"
      |> String.replace("+", "%2B")

    events = fn kinds ->
      c
      |> get_json("/events?#{range}&kind=#{kinds}&limit=200")
      |> json_response(200)
      |> get_in(["data", "events"])
    end

    housekeeping? = &String.match?(&1["raw_kind"], ~r/^source_|watermark/)

    for i <- 1..3 do
      at = DateTime.add(now, -60 * i)

      {:ok, _} =
        %{
          event_id: "watermark-#{i}-#{System.unique_integer([:positive])}",
          organization_id: c.org.organization_id,
          mission_id: c.mission.mission_id,
          occurred_at: at,
          recorded_at: at,
          effective_at: at,
          category: :data_source,
          kind: :source_watermark_advanced,
          severity: :info,
          subject: %{kind: :data_source, id: "questdb"},
          current: %{complete_through: DateTime.to_iso8601(at)}
        }
        |> OperationalEvent.new()
        |> OperationalEvents.persist_event()
    end

    data = events.("data")
    assert Enum.any?(data, housekeeping?)

    default = events.("limit,flight_event,contact,command,config,operator")
    assert default != []
    refute Enum.any?(default, housekeeping?)

    hour =
      "from=#{DateTime.add(now, -3_600)}&to=#{DateTime.add(now, 60)}"
      |> String.replace("+", "%2B")

    density =
      c
      |> get_json("/events/density?#{hour}&bucket_s=600&kind=data")
      |> json_response(200)

    assert Enum.sum(
             for b <- density["data"]["buckets"], k <- ~w(critical caution nominal info), do: b[k]
           ) > 0
  end
end
