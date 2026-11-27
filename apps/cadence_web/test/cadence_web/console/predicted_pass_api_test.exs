defmodule CadenceWeb.Console.PredictedPassAPITest do
  @moduledoc "GET /api/v1/missions/:id/predicted-passes and its spacecraft path (#891)."
  use CadenceWeb.ConnCase, async: true

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias Cadence.GroundNetworks.{ElementSets, PredictedPasses}
  alias Cadence.Organizations
  alias CadenceWeb.{ControlPlaneApiFixtures, TestFixtures}

  @now ~U[2026-11-27 00:00:00.000000Z]
  @from "2026-11-27T00:00:00Z"
  @to "2026-11-28T00:00:00Z"

  setup %{conn: conn} do
    fixture = ControlPlaneApiFixtures.bootstrap(conn)
    {:ok, organization} = Organizations.fetch_organization(fixture.organization_id)
    admin = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, organization, role: :organization_admin)
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(member, organization, role: :member)
    org = fixture.organization_id
    mission = fixture.mission_id

    crafts =
      for {i, raan} <- [{1, 10.0}, {2, 130.0}, {3, 250.0}] do
        ControlPlaneApiFixtures.persist_api_spacecraft!(org, mission, %{
          spacecraft_id: "craft-predicted-#{i}",
          display_name: "Predicted #{i}",
          scid: 700 + i
        }).spacecraft_id
        |> tap(fn id ->
          {:ok, _} =
            ElementSets.submit(org, mission, [%{spacecraft_id: id, input: {:omm, omm(raan)}}],
              actor: %{"actor_kind" => "user", "user_id" => "seed"},
              source: "manual",
              now: @now
            )
        end)
      end

    svalbard = station!(org, mission, "Svalbard", "SVA", {78.23, 15.41})
    _unlocated = station!(org, mission, "Nowhere", "NOW", nil)
    {:ok, _} = PredictedPasses.run(org, mission, :full, @now)

    Map.merge(fixture, %{
      crafts: crafts,
      svalbard: svalbard,
      admin: session_conn(TestFixtures.member_session_token!(admin)),
      member: session_conn(TestFixtures.member_session_token!(member)),
      path: "/api/v1/missions/#{mission}/predicted-passes"
    })
  end

  test "pages the mission's passes in AOS order with names, SCIDs and coverage", c do
    first = get_json(c.member, c.path, %{from: @from, to: @to, limit: 5})

    assert [row | _] = first["data"]
    assert length(first["data"]) == 5

    assert %{
             "id" => _,
             "aos" => _,
             "tca" => _,
             "los" => _,
             "max_elevation_deg" => elevation,
             "aos_azimuth_deg" => _,
             "los_azimuth_deg" => _,
             "spacecraft" => %{"id" => _, "name" => "Predicted " <> _, "scid" => scid},
             "station" => %{"id" => svalbard, "display_name" => "Svalbard", "code" => "SVA"},
             "element_set" => %{"id" => _, "epoch" => "2026-11-26T12:00:00.000000Z"},
             "computed_at" => "2026-11-27T00:00:00.000000Z"
           } = row

    assert svalbard == c.svalbard and elevation >= 5.0 and scid in 701..703

    assert %{
             "horizon_end" => "2026-12-04T00:00:00.000000Z",
             "computed_at" => "2026-11-27T00:00:00.000000Z",
             "unpredicted" => %{
               "spacecraft_without_element_set" => 0,
               "spacecraft_deep_space" => 0,
               "stations_without_location" => 1,
               "passes_not_bracketed" => 0
             }
           } = first["meta"]["coverage"]

    all = walk(c, %{from: @from, to: @to, limit: 5})
    aos = Enum.map(all, & &1["aos"])
    assert aos == Enum.sort(aos) and length(Enum.uniq_by(all, & &1["id"])) == length(all)

    # Every page repeats the coverage; the walk ends with a null cursor.
    assert length(all) > 5
  end

  test "includes a pass already in view and narrows by spacecraft or station", c do
    [pass | _] = walk(c, %{from: @from, to: @to, limit: 500})
    {:ok, aos, 0} = DateTime.from_iso8601(pass["aos"])
    mid = aos |> DateTime.add(60) |> DateTime.to_iso8601()

    in_view = get_json(c.member, c.path, %{from: mid, to: @to})["data"]
    assert Enum.any?(in_view, &(&1["id"] == pass["id"]))

    craft = hd(c.crafts)

    spacecraft_path =
      String.replace(c.path, "/predicted-passes", "/spacecraft/#{craft}/predicted-passes")

    two_weeks = "2026-12-11T00:00:00Z"

    for page <- [
          get_json(c.member, c.path, %{from: @from, to: two_weeks, spacecraft_id: craft}),
          get_json(c.member, spacecraft_path, %{from: @from, to: two_weeks})
        ] do
      assert page["data"] != [] and Enum.all?(page["data"], &(&1["spacecraft"]["id"] == craft))
    end

    by_station = get_json(c.member, c.path, %{from: @from, to: @to, station_id: c.svalbard})
    assert Enum.all?(by_station["data"], &(&1["station"]["id"] == c.svalbard))
    assert by_station["meta"]["coverage"]["unpredicted"]["stations_without_location"] == 0
  end

  test "refuses bad windows and parameters with the named field or code", c do
    craft = hd(c.crafts)

    for {params, field} <- [
          {%{to: @to}, "from"},
          {%{from: @from}, "to"},
          {%{from: "yesterday", to: @to}, "from"},
          {%{from: @from, to: @to, limit: 501}, "limit"},
          {%{from: @from, to: @to, cursor: "nope"}, "cursor"},
          {%{from: @from, to: @to, station_id: "station-missing"}, "station_id"},
          {%{from: @from, to: @to, spacecraft_id: "craft-missing"}, "spacecraft_id"},
          {%{from: @to, to: @from}, "to"},
          {%{from: @from, to: @from}, "to"}
        ] do
      assert %{"error" => %{"code" => "invalid_params", "details" => %{"field" => ^field}}} =
               c.member |> get(c.path, params) |> json_response(422)
    end

    for {params, max_days} <- [
          {%{from: @from, to: "2026-11-28T00:00:01Z"}, 1},
          {%{from: @from, to: "2026-12-12T00:00:00Z", spacecraft_id: craft}, 14}
        ] do
      assert %{
               "error" => %{
                 "code" => "predicted_pass_window_too_long",
                 "details" => %{"max_days" => ^max_days}
               }
             } = c.member |> get(c.path, params) |> json_response(422)
    end
  end

  test "a member reads, only an admin recomputes, and a service identity reaches none of it", c do
    assert %{"error" => %{"code" => "forbidden"}} =
             c.member |> post(c.path <> "/recompute", %{}) |> json_response(403)

    assert %{"data" => %{"run_id" => "pass_prediction_run_" <> _ = run_id, "status" => "queued"}} =
             c.admin |> post(c.path <> "/recompute", %{}) |> json_response(202)

    # A repeat while that run is open answers the same run.
    assert %{"data" => %{"run_id" => ^run_id}} =
             c.admin |> post(c.path <> "/recompute", %{}) |> json_response(202)

    for {method, path} <- [{:get, c.path}, {:post, c.path <> "/recompute"}] do
      assert %{"error" => %{"code" => "service_not_allowed"}} =
               build_conn()
               |> ControlPlaneApiFixtures.authorize(c.api_token)
               |> dispatch(@endpoint, method, path, %{from: @from, to: @to})
               |> json_response(403)
    end
  end

  defp walk(c, params, acc \\ []) do
    page = get_json(c.member, c.path, params)
    acc = acc ++ page["data"]

    case page["meta"]["next_cursor"] do
      nil -> acc
      cursor -> walk(c, Map.put(params, :cursor, cursor), acc)
    end
  end

  defp get_json(conn, path, params), do: conn |> get(path, params) |> json_response(200)

  defp station!(org, mission, name, code, at) do
    location =
      case at do
        {lat, lon} -> %{latitude_deg: lat, longitude_deg: lon, height_m: 0.0}
        nil -> nil
      end

    id = "ground_station_#{code}_#{System.unique_integer([:positive])}"

    {:ok, _} =
      GroundStationStore.persist_ground_station(
        org,
        GroundStation.new(%{
          ground_station_id: id,
          organization_id: org,
          mission_id: mission,
          display_name: name,
          code: code,
          location: location
        })
      )

    id
  end

  defp omm(raan) do
    %{
      "EPOCH" => "2026-11-26T12:00:00",
      "MEAN_MOTION" => 15.2,
      "ECCENTRICITY" => 0.0005,
      "INCLINATION" => 97.6,
      "RA_OF_ASC_NODE" => raan,
      "ARG_OF_PERICENTER" => 90.0,
      "MEAN_ANOMALY" => 270.0,
      "BSTAR" => 2.0e-5
    }
  end

  defp session_conn(session),
    do: Plug.Test.init_test_session(build_conn(), %{user_session_token: session})
end
