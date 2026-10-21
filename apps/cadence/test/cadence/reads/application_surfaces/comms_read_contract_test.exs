defmodule Cadence.Reads.ApplicationSurfaces.CommsReadContractTest do
  use Cadence.DataCase, async: false

  alias Cadence.Applications.{HostContext, SurfaceQueryRequest}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{GroundStation, GroundStationStore, RoutingRule, RoutingRuleStore}
  alias Cadence.Comms.{Transport, TransportStore}
  alias Cadence.Reads.ApplicationSurfaces.Comms
  alias Cadence.Reads.Comms.Pages
  alias Cadence.{Spacecraft, SpacecraftStore}

  @features Path.expand("../../../../../../frontend/modules/communications/src/features", __DIR__)
  @org "org-comms-read-contract"
  @mission "mission-comms-read-contract"

  setup do
    persist_mission_scope(@org, @mission)

    scope = %Scope{
      actor_kind: :user,
      organization_id: @org,
      mission_id: @mission,
      user: %{user_id: "comms-reader"},
      organization_membership: %{lifecycle_state: :active}
    }

    {:ok, spacecraft} =
      SpacecraftStore.persist_spacecraft(
        @org,
        Spacecraft.new(%{mission_id: @mission, display_name: "Firebird", scid: 42})
      )

    transport = transport!("Lab TCP")

    {:ok, station} =
      GroundStationStore.persist_ground_station(
        @org,
        GroundStation.new(%{
          mission_id: @mission,
          display_name: "Goldstone",
          provider: "DSN",
          region: "California"
        })
      )

    {:ok, rule} =
      RoutingRuleStore.create_routing_rule(
        @org,
        RoutingRule.new(%{
          mission_id: @mission,
          spacecraft_id: spacecraft.spacecraft_id,
          display_name: "Firebird downlink",
          purpose_label: "Telemetry",
          direction: :inbound,
          transport_id: transport.transport_id,
          transport_version: transport.version,
          role: :primary
        })
      )

    %{scope: scope, transport: transport, station: station, rule: rule}
  end

  test "real scoped overview, validation, collections and details satisfy feature consumers",
       context do
    for {surface, feature, validator, params} <- [
          {"overview", "overview", "readOverview", %{}},
          {"validation", "setup-validation", "readValidation", %{}},
          {"transports", "transports", "readDirectory", %{}},
          {"routing", "routing", "readDirectory", %{}},
          {"ground_stations", "ground-stations", "readDirectory", %{}},
          {"transport", "transports", "readDetail",
           %{"transport_id" => context.transport.transport_id}},
          {"routing_detail", "routing", "readDetail",
           %{"routing_rule_id" => context.rule.routing_rule_id}},
          {"ground_station", "ground-stations", "readDetail",
           %{"ground_station_id" => context.station.ground_station_id}}
        ] do
      payload = load!(context.scope, surface, params)
      assert_consumer(payload, feature, validator)
    end
  end

  test "pagination clamps both the page metadata and fetched rows, including searches", context do
    transport!("Zulu TCP")

    for page <- ["1", "2", "999"] do
      payload = load!(context.scope, "transports", %{"page" => page, "pageSize" => "1"})
      assert_consumer(payload, "transports", "readDirectory")
      assert length(payload["data"]["items"]) == 1
      assert payload["data"]["page"] == if(page == "1", do: 1, else: 2)
    end

    payload = load!(context.scope, "transports", %{"q" => "Zulu", "page" => "999"})
    assert_consumer(payload, "transports", "readDirectory")
    assert [%{"display_name" => "Zulu TCP"}] = payload["data"]["items"]

    for {surface, feature} <- [
          {"transports", "transports"},
          {"routing", "routing"},
          {"ground_stations", "ground-stations"}
        ] do
      payload = load!(context.scope, surface, %{"q" => "no-such-record", "page" => "999"})
      assert_consumer(payload, feature, "readDirectory")
      assert payload["data"]["page"] == 1
      assert payload["data"]["items"] == []
    end
  end

  test "validation pagination preserves the typed feature contract", context do
    for index <- 1..25 do
      {:ok, _} =
        SpacecraftStore.persist_spacecraft(
          @org,
          Spacecraft.new(%{mission_id: @mission, display_name: "Needs setup #{index}"})
        )
    end

    for page <- ["1", "2", "999"] do
      payload = load!(context.scope, "validation", %{"page" => page})
      assert payload["data"]["total_count"] > 20
      assert_consumer(payload, "setup-validation", "readValidation")
    end
  end

  test "collection ordering is applied before pagination, including descending URLs", context do
    transport!("Zulu TCP")

    {:ok, _} =
      GroundStationStore.persist_ground_station(@org, %{
        context.station
        | ground_station_id: "station-sorting-2",
          display_name: "Zulu Station"
      })

    {:ok, _} =
      RoutingRuleStore.create_routing_rule(@org, %{
        context.rule
        | routing_rule_id: "rule-sorting-2",
          display_name: "Zulu Routing",
          purpose_label: "Alpha"
      })

    for {surface, names} <- [
          {"transports", ["Lab TCP", "Zulu TCP"]},
          {"ground_stations", ["Goldstone", "Zulu Station"]},
          {"routing", ["Firebird downlink", "Zulu Routing"]}
        ],
        {direction, expected} <- [{"asc", names}, {"desc", Enum.reverse(names)}] do
      actual =
        for page <- ["1", "2"] do
          payload =
            load!(context.scope, surface, %{
              "page" => page,
              "pageSize" => "1",
              "sort" => "display_name",
              "dir" => direction
            })

          assert [%{"display_name" => name}] = payload["data"]["items"]
          assert payload["data"]["dir"] == direction
          name
        end

      assert actual == expected
    end
  end

  test "real scoped setup forms satisfy their feature consumers", context do
    for {surface, feature, validator, params} <- [
          {"transport_new", "transports", "readForm", %{}},
          {"routing_new", "routing", "readForm",
           %{"spacecraft_id" => context.rule.spacecraft_id}},
          {"ground_station_new", "ground-stations", "readForm", %{}},
          {"ground_station_edit", "ground-stations", "readEditForm",
           %{"ground_station_id" => context.station.ground_station_id}}
        ] do
      payload = load!(context.scope, surface, params)
      data = get_in(payload, ["trusted_surface", "data"]) || payload["data"]

      assert_consumer(
        %{"navigation" => payload["navigation"], "data" => data},
        feature,
        validator,
        "form-validation.ts"
      )
    end
  end

  test "scope and query versions cannot be forged", context do
    assert {:error, _} =
             Comms.load(
               %{context.scope | organization_id: "another-org"},
               HostContext.mission(@mission),
               request("transports", %{})
             )

    assert {:error, _} =
             Comms.load(
               %{context.scope | mission_id: "another-mission"},
               HostContext.mission(@mission),
               request("transports", %{})
             )

    assert {:error, _} =
             Comms.load(context.scope, HostContext.mission(@mission), %{
               request("transports", %{})
               | query_version: 2
             })

    assert {:error, _} =
             Comms.load(
               context.scope,
               HostContext.mission(@mission),
               request("transports", %{"mission_id" => "another-mission"})
             )
  end

  test "every domain page rejects missing, revoked and cross-mission authority", context do
    for {page, params} <- page_requests(context),
        scope <- [
          %Scope{organization_id: @org},
          %{context.scope | user: nil},
          %{context.scope | organization_membership: nil},
          %{context.scope | organization_membership: %{lifecycle_state: :revoked}},
          %{context.scope | organization_id: "another-org"},
          %{context.scope | mission_id: "another-mission"}
        ] do
      assert {:error, _} = Pages.load(scope, @mission, page, params)
      assert {:error, _} = Comms.load(scope, HostContext.mission(@mission), request(page, params))
    end
  end

  test "domain reads accept organization scope but reauthorize every refresh", context do
    scope = %{context.scope | mission_id: nil}

    for {page, params} <- page_requests(context) do
      assert {:ok, _} = Pages.load(scope, @mission, page, params)

      assert {:error, _} =
               Pages.load(%{scope | organization_membership: nil}, @mission, page, params)
    end
  end

  test "domain reads reject unknown pages, malformed params and mismatched resources", context do
    for {page, params} <- [
          {"unknown", %{}},
          {"provider_list", %{}},
          {"__proto__", %{}},
          {"transports", nil},
          {"transports", []},
          {"transports", %{page: "1"}},
          {"transports", %{"page" => "10001"}},
          {"transports", %{"pageSize" => "101"}},
          {"transports", %{"mission_id" => "another-mission"}},
          {"transports", %{"application_key" => "comms"}},
          {"transport", %{"transport_id" => "missing-transport"}},
          {"routing_detail", %{"routing_rule_id" => "missing-rule"}},
          {"ground_station", %{"ground_station_id" => "../another-station"}},
          {"ground_station_edit", %{"ground_station_id" => "missing-station"}}
        ] do
      assert {:error, _} = Pages.load(context.scope, @mission, page, params)
    end

    assert {:error, _} = Pages.load(nil, @mission, "overview")
    assert {:error, _} = Pages.load(context.scope, "../mission", "overview")
  end

  test "the legacy adapter still requires exact application, surface, query and placement identities",
       context do
    base = request("transports", %{})

    for forged <- [
          %{base | application_key: "ops_console"},
          %{base | application_version: 2},
          %{base | surface_id: "overview"},
          %{base | surface_version: 2},
          %{base | query_id: "cadence.comms.overview"},
          %{base | query_version: 2}
        ] do
      assert {:error, :unsupported_application_surface_query} =
               Comms.load(context.scope, HostContext.mission(@mission), forged)
    end

    assert {:error, :unsupported_application_surface_query} =
             Comms.load(context.scope, HostContext.spacecraft(@mission, "spacecraft"), base)
  end

  defp page_requests(context) do
    [
      {"overview", %{}},
      {"validation", %{}},
      {"transports", %{}},
      {"routing", %{}},
      {"ground_stations", %{}},
      {"transport", %{"transport_id" => context.transport.transport_id}},
      {"routing_detail", %{"routing_rule_id" => context.rule.routing_rule_id}},
      {"ground_station", %{"ground_station_id" => context.station.ground_station_id}},
      {"transport_new", %{}},
      {"routing_new", %{}},
      {"ground_station_new", %{}},
      {"ground_station_edit", %{"ground_station_id" => context.station.ground_station_id}}
    ]
  end

  defp load!(scope, surface, params) do
    result = Pages.load(scope, @mission, surface, params)
    assert match?({:ok, _}, result), "expected #{surface} to load: #{inspect(result)}"
    assert Comms.load(scope, HostContext.mission(@mission), request(surface, params)) == result
    {:ok, payload} = result

    payload
  end

  defp request(surface, params) do
    %SurfaceQueryRequest{
      application_key: "comms",
      application_version: 1,
      surface_id: surface,
      surface_version: 1,
      query_id: "cadence.comms." <> surface,
      query_version: 1,
      params: params
    }
  end

  defp transport!(name) do
    {:ok, transport} =
      TransportStore.persist_transport(
        @org,
        Transport.new(%{
          mission_id: @mission,
          display_name: name,
          transport_kind: :tcp_socket,
          direction_capability: :inbound,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "listen",
            "direction_capability" => "inbound",
            "host" => "0.0.0.0",
            "port" => "5000",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          }
        })
      )

    transport
  end

  defp assert_consumer(payload, feature, validator, filename \\ "read-validation.ts") do
    path = Path.join([@features, feature, filename])

    node =
      System.find_executable("node") ||
        flunk("Node is required for the Communications DTO contract")

    script = """
    import * as consumer from #{Jason.encode!(path)};
    consumer.#{validator}(JSON.parse(process.argv[1]), {missionId: #{Jason.encode!(@mission)}});
    """

    {output, status} =
      System.cmd(
        node,
        ["--no-warnings", "--input-type=module", "-e", script, Jason.encode!(payload)],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
