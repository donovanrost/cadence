defmodule CadenceWeb.Console.ElementSetAPITest do
  use CadenceWeb.ConnCase, async: true

  alias Cadence.Organizations
  alias Cadence.Repo
  alias Cadence.SpacecraftStore.SpacecraftRow
  alias CadenceWeb.{ControlPlaneApiFixtures, TestFixtures}

  # ISS (ZARYA), element set 292 of 2008-09-20.
  @line1 "1 25544U 98067A   08264.51782528 -.00002182  00000-0 -11606-4 0  2927"
  @line2 "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.72125391563537"
  @iss "ISS (ZARYA)\n#{@line1}\n#{@line2}"

  setup %{conn: conn} do
    fixture = ControlPlaneApiFixtures.bootstrap(conn)
    {:ok, organization} = Organizations.fetch_organization(fixture.organization_id)
    admin = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, organization, role: :organization_admin)
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(member, organization, role: :member)

    spacecraft =
      ControlPlaneApiFixtures.persist_api_spacecraft!(
        fixture.organization_id,
        fixture.mission_id,
        %{
          spacecraft_id: "craft-element-sets",
          display_name: "Element set fixture"
        }
      )

    path = "/api/v1/missions/#{fixture.mission_id}"

    Map.merge(fixture, %{
      craft: spacecraft.spacecraft_id,
      admin: session_conn(TestFixtures.member_session_token!(admin)),
      member: session_conn(TestFixtures.member_session_token!(member)),
      path: path,
      craft_path: path <> "/spacecraft/#{spacecraft.spacecraft_id}/element-sets"
    })
  end

  test "stores a TLE, answers a re-send with 200 and reads it back as current", c do
    assert %{"data" => set, "meta" => %{"result" => "created"}} =
             c.admin |> post(c.craft_path, %{tle: @iss}) |> json_response(201)

    assert %{
             "format" => "tle",
             "source" => "manual",
             "epoch" => "2008-09-20T12:25:40.104192Z",
             "norad_id" => 25_544,
             "object_name" => "ISS (ZARYA)",
             "elements" => %{
               "mean_motion_rev_per_day" => 15.72125391,
               "eccentricity" => 0.0006703
             },
             "created_by" => %{"kind" => "user"}
           } = set

    assert %{"data" => ^set, "meta" => %{"result" => "unchanged"}} =
             c.admin |> post(c.craft_path, %{tle: @iss}) |> json_response(200)

    assert %{"data" => ^set} = c.member |> get(c.craft_path <> "/current") |> json_response(200)
  end

  test "stores an OMM and pages history newest epoch first", c do
    omm = fn day ->
      %{
        "EPOCH" => "2026-11-2#{day}T00:00:00.000000",
        "MEAN_MOTION" => 15.05,
        "ECCENTRICITY" => 0.0001,
        "INCLINATION" => 53.0,
        "RA_OF_ASC_NODE" => 10.0,
        "ARG_OF_PERICENTER" => 90.0,
        "MEAN_ANOMALY" => 270.0,
        "BSTAR" => 5.0e-5
      }
    end

    for day <- 1..3,
        do: assert(%{} = c.admin |> post(c.craft_path, %{omm: omm.(day)}) |> json_response(201))

    assert %{
             "data" => [%{"epoch" => "2026-11-23T00:00:00.000000Z"} = first, second],
             "meta" => %{"next_cursor" => cursor}
           } =
             c.member |> get(c.craft_path <> "?limit=2") |> json_response(200)

    assert first["format"] == "omm" and second["epoch"] == "2026-11-22T00:00:00.000000Z"

    assert %{
             "data" => [%{"epoch" => "2026-11-21T00:00:00.000000Z"}],
             "meta" => %{"next_cursor" => nil}
           } =
             c.member |> get(c.craft_path <> "?limit=2&cursor=#{cursor}") |> json_response(200)

    assert %{"error" => %{"code" => "invalid_params", "details" => %{"field" => "cursor"}}} =
             c.member |> get(c.craft_path <> "?cursor=bad") |> json_response(422)
  end

  test "refuses a bad set with its own code and an unknown spacecraft with 404", c do
    broken = String.replace(@iss, "2927", "2928")

    assert %{
             "error" => %{
               "code" => "element_set_bad_checksum",
               "details" => %{"field" => "line1"}
             }
           } =
             c.admin |> post(c.craft_path, %{tle: broken}) |> json_response(422)

    assert %{"error" => %{"code" => "invalid_params"}} =
             c.admin |> post(c.craft_path, %{tle: @iss, omm: %{}}) |> json_response(422)

    assert %{"error" => %{"code" => "spacecraft_not_found"}} =
             c.admin
             |> post(c.path <> "/spacecraft/unknown/element-sets", %{tle: @iss})
             |> json_response(404)

    assert %{"data" => nil} = c.member |> get(c.craft_path <> "/current") |> json_response(200)
  end

  test "a member reads but doesn't write; a service identity reaches none of it", c do
    assert %{"error" => %{"code" => "forbidden"}} =
             c.member |> post(c.craft_path, %{tle: @iss}) |> json_response(403)

    assert %{"error" => %{"code" => "forbidden"}} =
             c.member
             |> post(c.path <> "/element-sets", %{
               element_sets: [%{spacecraft_id: c.craft, tle: @iss}]
             })
             |> json_response(403)

    for {method, path} <- [
          {:get, c.craft_path},
          {:get, c.craft_path <> "/current"},
          {:post, c.craft_path},
          {:post, c.path <> "/element-sets"}
        ] do
      assert %{"error" => %{"code" => "service_not_allowed"}} =
               build_conn()
               |> ControlPlaneApiFixtures.authorize(c.api_token)
               |> dispatch(@endpoint, method, path, %{tle: @iss})
               |> json_response(403)
    end
  end

  test "bulk answers each item and takes 1,000 spacecraft in one request", c do
    crafts = insert_spacecraft!(c.organization_id, c.mission_id, 1_000)
    items = for {craft, i} <- Enum.with_index(crafts), do: %{spacecraft_id: craft, tle: tle(i)}

    assert %{"data" => %{"results" => results, "counts" => counts}} =
             c.admin
             |> post(c.path <> "/element-sets", %{element_sets: items})
             |> json_response(200)

    assert counts == %{"created" => 1_000, "unchanged" => 0, "refused" => 0}
    assert results |> Enum.map(& &1["index"]) == Enum.to_list(0..999)
    assert hd(results)["element_set"]["spacecraft_id"] == hd(crafts)

    mixed = [
      %{spacecraft_id: hd(crafts), tle: tle(0)},
      %{spacecraft_id: "craft-missing", tle: tle(1)},
      %{spacecraft_id: c.craft, tle: "garbage"},
      %{spacecraft_id: c.craft},
      %{tle: tle(2)}
    ]

    assert %{"data" => %{"results" => results, "counts" => counts}} =
             c.admin
             |> post(c.path <> "/element-sets", %{element_sets: mixed})
             |> json_response(200)

    assert counts == %{"created" => 0, "unchanged" => 1, "refused" => 4}

    assert [
             %{"index" => 0, "result" => "unchanged"},
             %{
               "index" => 1,
               "result" => "refused",
               "error" => %{"code" => "spacecraft_not_found"}
             },
             %{"index" => 2, "error" => %{"code" => "element_set_unparseable"}},
             %{"index" => 3, "error" => %{"code" => "invalid_params"}},
             %{"index" => 4, "spacecraft_id" => nil, "error" => %{"code" => "invalid_params"}}
           ] = results

    too_many = List.duplicate(%{spacecraft_id: c.craft, tle: @iss}, 1_001)

    assert %{"error" => %{"code" => "element_set_batch_too_large"}} =
             c.admin
             |> post(c.path <> "/element-sets", %{element_sets: too_many})
             |> json_response(422)
  end

  defp session_conn(session),
    do: Plug.Test.init_test_session(build_conn(), %{user_session_token: session})

  defp insert_spacecraft!(organization_id, mission_id, count) do
    at = DateTime.utc_now()
    suffix = System.unique_integer([:positive])

    rows =
      for i <- 1..count do
        %{
          spacecraft_id: "craft-bulk-#{suffix}-#{i}",
          organization_id: organization_id,
          mission_id: mission_id,
          display_name: "Bulk #{i}",
          metadata: %{},
          lifecycle_state: "active",
          inserted_at: at
        }
      end

    {^count, _} = Repo.insert_all(SpacecraftRow, rows)
    Enum.map(rows, & &1.spacecraft_id)
  end

  # A synthetic LEO set (2026-11-21, ~550 km, 53°) with its RAAN spread by `i`.
  defp tle(i) do
    line1 = "1 99999U 26001A   26325.50000000  .00001000  00000-0  50000-4 0  999"
    raan = :erlang.float_to_binary(i * 0.36, decimals: 4) |> String.pad_leading(8)
    line2 = "2 99999  53.0000 #{raan} 0001000  90.0000 270.0000 15.0500000000001"
    line1 <> checksum(line1) <> "\n" <> line2 <> checksum(line2)
  end

  defp checksum(line) do
    line
    |> String.to_charlist()
    |> Enum.reduce(0, fn
      char, sum when char in ?0..?9 -> sum + char - ?0
      ?-, sum -> sum + 1
      _char, sum -> sum
    end)
    |> rem(10)
    |> Integer.to_string()
  end
end
