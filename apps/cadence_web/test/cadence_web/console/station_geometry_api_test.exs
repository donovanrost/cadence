defmodule CadenceWeb.Console.StationGeometryAPITest do
  @moduledoc """
  A ground station's location and elevation mask over /api/v1 (#890): the mission's own value
  is staged like any station field (`ground_station` change sets, session + CSRF), the station
  read shows the location in use and its source, and a service identity reaches neither.
  """
  # Mutates :activation_governance application env.
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Comms.StationLocations
  alias Cadence.Organizations
  alias CadenceWeb.{ControlPlaneApiFixtures, TestFixtures}

  setup %{conn: conn} do
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: false)
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)

    fixture = ControlPlaneApiFixtures.bootstrap(conn)
    {:ok, organization} = Organizations.fetch_organization(fixture.organization_id)
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(member, organization, role: :member)
    outsider = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(outsider, TestFixtures.persist_org!(), role: :member)

    Map.merge(fixture, %{
      member: member,
      outsider: outsider,
      base: "/api/v1/missions/#{fixture.mission_id}"
    })
  end

  defp stage(c, user, document) do
    op = %{"kind" => "ground_station", "action" => "create", "document" => document}

    user
    |> TestFixtures.member_conn()
    |> post(c.base <> "/config/stage", %{"summary" => "Station", "ops" => [op]})
  end

  defp apply_station(c, document) do
    %{"data" => %{"change_set_id" => id, "version" => version}} =
      c |> stage(c.member, document) |> json_response(201)

    c.member
    |> TestFixtures.member_conn()
    |> post(c.base <> "/config/change-sets/#{id}/submit", %{
      "reason" => "Add the station",
      "expected_version" => version
    })
    |> json_response(200)
  end

  defp stations(c) do
    c.member
    |> TestFixtures.member_conn()
    |> get(c.base <> "/ground-stations")
    |> json_response(200)
    |> get_in(["data", "stations"])
  end

  test "a staged location is read back as the mission's, with the mask", c do
    apply_station(c, %{
      "display_name" => "Svalbard",
      "latitude_deg" => 78.23,
      "longitude_deg" => 15.41,
      "height_m" => 450,
      "elevation_mask_deg" => 7.5
    })

    assert [
             %{
               "display_name" => "Svalbard",
               "location" => %{
                 "latitude_deg" => 78.23,
                 "longitude_deg" => 15.41,
                 "height_m" => 450.0,
                 "source" => "mission"
               },
               "provider_location" => nil,
               "elevation_mask_deg" => 7.5
             }
           ] = stations(c)
  end

  test "an unlocated station reads null until a provider reports one", c do
    apply_station(c, %{"display_name" => "Hawaii"})
    assert [%{"id" => id, "location" => nil, "elevation_mask_deg" => 5.0}] = stations(c)

    report = [%{"id" => id, "location" => %{"latitude_deg" => 19.0, "longitude_deg" => -155.7}}]

    {:ok, %{recorded: 1}} =
      StationLocations.record_provider_reports(c.organization_id, c.mission_id, "sim", report)

    assert [
             %{
               "location" => %{"latitude_deg" => 19.0, "source" => "provider"},
               "provider_location" => %{"latitude_deg" => 19.0, "reported_at" => reported_at}
             }
           ] = stations(c)

    assert {:ok, _at, 0} = DateTime.from_iso8601(reported_at)
  end

  test "an out-of-range value is refused with its field", c do
    for {document, path} <- [
          {%{"latitude_deg" => 95, "longitude_deg" => 0}, "latitude_deg"},
          {%{"latitude_deg" => 0, "longitude_deg" => 0, "elevation_mask_deg" => 90},
           "elevation_mask_deg"},
          {%{"latitude_deg" => 10}, "longitude_deg"}
        ] do
      assert %{"code" => "invalid_op", "details" => %{"errors" => errors}} =
               c
               |> stage(c.member, Map.put(document, "display_name", "Bad"))
               |> json_response(422)
               |> Map.fetch!("error")

      assert Enum.any?(errors, &(&1["path"] == path)), inspect(errors)
    end
  end

  test "someone outside the mission can't stage or read it; a service identity reaches neither",
       c do
    # Outside the mission it doesn't exist (no disclosure).
    assert %{"error" => %{"code" => "mission_not_found"}} =
             c |> stage(c.outsider, %{"display_name" => "X"}) |> json_response(404)

    assert %{"error" => %{"code" => "mission_not_found"}} =
             c.outsider
             |> TestFixtures.member_conn()
             |> get(c.base <> "/ground-stations")
             |> json_response(404)

    for {method, path} <- [{:post, "/config/stage"}, {:get, "/ground-stations"}] do
      assert %{"error" => %{"code" => "service_not_allowed"}} =
               build_conn()
               |> ControlPlaneApiFixtures.authorize(c.api_token)
               |> dispatch(@endpoint, method, c.base <> path, %{})
               |> json_response(403)
    end
  end
end
