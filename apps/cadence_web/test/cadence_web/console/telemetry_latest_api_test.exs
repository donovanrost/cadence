defmodule CadenceWeb.Console.TelemetryLatestAPITest do
  @moduledoc "Compose B2's Now column: latest values for a few points across many spacecraft."
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.{ControlPlaneApiFixtures, TestFixtures}

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    ControlPlaneApiFixtures.seed_mission_read_models(org.organization_id, mission.mission_id)

    {:ok, _activation} =
      Cadence.Activations.record_binding_set_activation(
        org.organization_id,
        mission.mission_id,
        "read-models",
        1,
        binding_set_content_sha256: String.duplicate("0", 64)
      )

    %{
      user: user,
      org: org.organization_id,
      mission_id: mission.mission_id,
      path: "/api/v1/missions/#{mission.mission_id}/telemetry/latest"
    }
  end

  defp latest(c, body), do: c.user |> TestFixtures.member_conn() |> post(c.path, body)

  test "one entry per spacecraft and point; no value yet is null", c do
    body = %{"point_ids" => ["HK.counter", "HK.nothing"], "spacecraft_ids" => ["spacecraft-001"]}
    values = c |> latest(body) |> json_response(200) |> get_in(["data", "values"])

    assert [counter, nothing] = values

    assert %{
             "spacecraft_id" => "spacecraft-001",
             "point_id" => "HK.counter",
             "value_json" => json
           } =
             counter

    assert is_binary(json) and is_binary(counter["received_at"]) and is_boolean(counter["stale"])

    assert nothing == %{
             "spacecraft_id" => "spacecraft-001",
             "point_id" => "HK.nothing",
             "value_json" => nil,
             "received_at" => nil,
             "stale" => false
           }
  end

  test "there is no spacecraft ceiling: a fleet over 500 is read in full", c do
    org = c.org

    crafts =
      for n <- 1..620 do
        id = "fleet-#{String.pad_leading(Integer.to_string(n), 4, "0")}"

        {:ok, _} =
          Cadence.SpacecraftStore.persist_spacecraft(
            org,
            Cadence.Spacecraft.new(%{
              spacecraft_id: id,
              organization_id: org,
              mission_id: c.mission_id,
              display_name: id
            })
          )

        id
      end

    body = %{"point_ids" => ["HK.counter", "HK.nothing"], "spacecraft_ids" => crafts}
    values = c |> latest(body) |> json_response(200) |> get_in(["data", "values"])

    assert length(values) == 1_240
    assert Enum.map(values, & &1["spacecraft_id"]) |> Enum.uniq() == crafts
    assert Enum.all?(values, &(&1["value_json"] == nil))
  end

  test "a request is bounded by its response size, not by a craft count", c do
    long = String.duplicate("x", 250)
    crafts = for n <- 1..4_000, do: "#{long}#{n}"
    points = for n <- 1..10, do: "HK.p#{n}"

    assert %{"details" => %{"max_response_bytes" => 8_000_000, "spacecraft_ids" => message}} =
             c
             |> latest(%{"point_ids" => points, "spacecraft_ids" => crafts})
             |> json_response(422)
             |> Map.fetch!("error")

    assert message =~ "the response would be about"
  end

  test "it's capped and mission-scoped", c do
    many = for i <- 1..11, do: "HK.p#{i}"

    assert %{"details" => %{"point_ids" => _}} =
             c
             |> latest(%{"point_ids" => many, "spacecraft_ids" => ["spacecraft-001"]})
             |> json_response(422)
             |> Map.fetch!("error")

    assert %{"details" => %{"spacecraft_ids" => _, "unknown" => ["ghost"]}} =
             c
             |> latest(%{"point_ids" => ["HK.counter"], "spacecraft_ids" => ["ghost"]})
             |> json_response(422)
             |> Map.fetch!("error")

    assert c |> latest(%{}) |> json_response(422)
  end
end
