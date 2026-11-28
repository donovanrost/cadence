defmodule CadenceWeb.Console.CommsAPITest do
  # Mutates :activation_governance application env in one test.
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Comms.{GroundStation, GroundStationStore}
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)

    %{
      user: user,
      org: org,
      mission: mission,
      base: "/api/v1/missions/#{mission.mission_id}"
    }
  end

  defp get_data(c, path),
    do:
      c.user
      |> TestFixtures.member_conn()
      |> get(c.base <> path)
      |> json_response(200)
      |> Map.fetch!("data")

  test "empty mission lists no stations, transports, providers or rules", c do
    assert get_data(c, "/ground-stations") == %{"stations" => []}
    assert get_data(c, "/providers") == %{"providers" => [], "permissions" => []}
    assert get_data(c, "/transports") == %{"transports" => []}
    assert get_data(c, "/routing-rules") == %{"rules" => [], "total" => 0, "next_cursor" => nil}
  end

  test "lists a ground station with unknown health and links", c do
    station =
      GroundStation.new(%{
        ground_station_id: "gs-svalbard",
        organization_id: c.org.organization_id,
        mission_id: c.mission.mission_id,
        display_name: "Svalbard",
        provider: "KSAT",
        region: "Arctic",
        code: "SVB"
      })

    {:ok, _} =
      GroundStationStore.persist_ground_station(c.org.organization_id, station)

    assert [row] = get_data(c, "/ground-stations")["stations"]

    assert %{
             "id" => "gs-svalbard",
             "display_name" => "Svalbard",
             "code" => "SVB",
             "provider" => "KSAT",
             "lifecycle_state" => "active",
             "transport_count" => nil,
             "health" => nil
           } = row
  end

  test "transport detail returns the editable document on the kind schema's paths", c do
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: false)
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)

    op = %{
      "kind" => "transport",
      "action" => "create",
      "document" => %{
        "display_name" => "Svalbard X-band",
        "configuration" => %{
          "mode" => "listen",
          "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        }
      }
    }

    conn = TestFixtures.member_conn(c.user)

    staged =
      conn
      |> post(c.base <> "/config/stage", %{"summary" => "Add", "ops" => [op]})
      |> json_response(201)

    %{"change_set_id" => set_id, "version" => version, "entity_ids" => [transport_id]} =
      staged["data"]

    c.user
    |> TestFixtures.member_conn()
    |> post("#{c.base}/config/change-sets/#{set_id}/submit", %{
      "reason" => "Add the Svalbard transport",
      "expected_version" => version
    })
    |> json_response(200)

    detail = get_data(c, "/transports/#{transport_id}")
    assert %{"id" => ^transport_id, "version" => 1, "lifecycle_state" => "active"} = detail
    document = detail["document"]
    assert document["display_name"] == "Svalbard X-band"

    schema = get_data(c, "/config/kinds/transport/schema")

    for path <-
          ~w(configuration.mode configuration.host configuration.port configuration.framing.mode configuration.tls.enabled) do
      assert Enum.any?(schema["fields"], &(&1["path"] == path)), "schema lacks #{path}"
      assert get_in(document, String.split(path, ".")) != nil, "document lacks #{path}"
    end

    assert get_in(document, ~w(configuration tls enabled)) == false

    conn = c.user |> TestFixtures.member_conn() |> get(c.base <> "/transports/nope")
    assert json_response(conn, 404)["error"]["code"] == "transport_not_found"
  end

  test "routing rules reject a bad page size", c do
    conn = c.user |> TestFixtures.member_conn() |> get(c.base <> "/routing-rules?limit=0")
    assert json_response(conn, 422)["error"]["details"]["limit"]
  end

  test "kind schemas generate station and transport forms", c do
    station = get_data(c, "/config/kinds/ground_station/schema")

    assert Enum.map(station["fields"], & &1["path"]) ==
             ~w(display_name code provider region latitude_deg longitude_deg height_m
                elevation_mask_deg metadata)

    code = Enum.find(station["fields"], &(&1["path"] == "code"))
    # Optional until set (ux U25); the pattern still applies to a code that is given.
    assert %{"required" => false, "pattern" => "^[A-Z0-9]{2,8}$"} = code
    # No mission providers yet, so provider is free text rather than an empty enum.
    assert Enum.find(station["fields"], &(&1["path"] == "provider"))["type"] == "string"
    # Comms parity (4): metadata is a JSON object, empty by default.
    assert %{"type" => "json", "default" => %{}, "required" => false} =
             Enum.find(station["fields"], &(&1["path"] == "metadata"))

    transport = get_data(c, "/config/kinds/transport/schema")
    paths = Enum.map(transport["fields"], & &1["path"])
    assert "configuration.mode" in paths
    assert "configuration.port" in paths
    assert "configuration.framing.fixed_message_bytes" in paths

    tls = Enum.find(transport["fields"], &(&1["path"] == "configuration.tls.enabled"))
    assert %{"type" => "boolean", "default" => false, "enum" => nil} = tls

    port = Enum.find(transport["fields"], &(&1["path"] == "configuration.port"))
    assert %{"type" => "integer", "range" => %{"min" => 1, "max" => 65_535}} = port

    conn = c.user |> TestFixtures.member_conn() |> get(c.base <> "/config/kinds/nope/schema")
    assert json_response(conn, 422)["error"]["code"] == "invalid_params"
  end

  test "the spacecraft_profile schema is the name plus the profile's framing and catalog fields",
       c do
    fields = get_data(c, "/config/kinds/spacecraft_profile/schema")["fields"]
    by_path = Map.new(fields, &{&1["path"], &1})

    assert hd(fields)["path"] == "display_name"

    assert ~w(display_name downlink_protocol uplink_protocol packet_protocol
              frame_parameters.frame_size frame_parameters.fecf catalog_revision_id) --
             Map.keys(by_path) == []

    assert %{"required" => true, "section" => "profile"} = by_path["display_name"]

    assert %{"required" => true, "type" => "enum", "default" => "tm", "section" => "framing"} =
             by_path["downlink_protocol"]

    assert %{"required" => false, "unit" => "bytes", "range" => %{"max" => 65_535}} =
             by_path["frame_parameters.frame_size"]

    # No catalog revisions in this mission: the reference keeps no choices.
    assert %{"type" => "reference", "section" => "catalog", "enum" => nil} =
             by_path["catalog_revision_id"]

    refute Map.has_key?(by_path, "routing_rules")
  end
end
