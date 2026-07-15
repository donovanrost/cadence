defmodule Cadence.Contacts.ProviderSchedulingTest do
  use Cadence.DataCase, async: false

  alias Cadence.Comms.{RoutingRule, Transport}
  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.TestSupport.FakeProviderClient

  setup do
    suffix = System.unique_integer([:positive])
    organization_id = "org-provider-scheduling-#{suffix}"
    mission_id = "mission-provider-scheduling-#{suffix}"
    persist_mission_scope(organization_id, mission_id)

    spacecraft = persist_spacecraft(organization_id, mission_id, suffix, "primary")
    _mapping = persist_mapping(organization_id, mission_id, spacecraft, suffix, "SIM-001")
    provider = persist_provider!(organization_id, mission_id, suffix)
    transport = persist_provider_transport!(organization_id, mission_id, provider, suffix)
    rule = persist_rule!(organization_id, mission_id, spacecraft, transport, suffix)

    %{
      organization_id: organization_id,
      mission_id: mission_id,
      spacecraft: spacecraft,
      provider: provider,
      transport: transport,
      rule: rule,
      suffix: suffix
    }
  end

  test "resolves exact Routing Rule, Transport, Provider, and profile versions", context do
    assert {:ok, %{routes: [route], findings: []}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               context.spacecraft.spacecraft_id
             )

    assert route.provider_spacecraft_ref == "SIM-001"
    assert route.routing_rule_id == context.rule.routing_rule_id
    assert route.transport_id == context.transport.transport_id
    assert route.transport_version == context.transport.version
    assert route.provider_id == context.provider.provider_id
    assert route.provider_version == context.provider.version
    assert route.service_profile_ref == %{"id" => "service-downlink", "version" => 3}
    assert route.delivery_profile_ref == %{"id" => "delivery-cadence", "version" => 7}

    starts_at = DateTime.utc_now() |> DateTime.add(120) |> DateTime.truncate(:second)
    ends_at = DateTime.add(starts_at, 3_600)
    opportunity = opportunity(route, starts_at)

    assert {:ok, %{route: searched_route, opportunities: [result]}} =
             ProviderScheduling.search_opportunities(
               context.organization_id,
               context.mission_id,
               route.route_key,
               %{
                 "spacecraft_id" => context.spacecraft.spacecraft_id,
                 "starts_at" => DateTime.to_iso8601(starts_at),
                 "ends_at" => DateTime.to_iso8601(ends_at)
               },
               client: FakeProviderClient,
               on_search: fn params ->
                 assert params["spacecraft_refs"] == ["SIM-001"]
                 assert params["service_profile_ref"] == "service-downlink"
                 refute Map.has_key?(params, "transport_id")
                 refute Map.has_key?(params, "run_id")
               end,
               search_response: {:ok, %{"data" => [opportunity]}}
             )

    assert searched_route.route_key == route.route_key
    assert result["route_key"] == route.route_key
    assert result["delivery_profile_ref"] == "delivery-cadence"
  end

  test "a newer Provider version does not rewrite the route's exact binding", context do
    assert {:ok, newer_provider} =
             GroundNetworks.version_provider(
               context.organization_id,
               context.mission_id,
               context.provider.provider_id,
               %{display_name: "Simulator staging"}
             )

    assert newer_provider.version == context.provider.version + 1

    assert {:ok, %{routes: [route]}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               context.spacecraft.spacecraft_id
             )

    assert route.provider_version == context.provider.version
    assert route.provider_display_name == context.provider.display_name
  end

  test "reports spacecraft mapping and Routing Rule readiness separately", context do
    unmapped =
      persist_spacecraft(context.organization_id, context.mission_id, context.suffix, "unmapped")

    assert {:ok, %{routes: [], findings: [%{code: :missing_source_endpoint}]}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               unmapped.spacecraft_id
             )

    unrouted =
      persist_spacecraft(context.organization_id, context.mission_id, context.suffix, "unrouted")

    _mapping =
      persist_mapping(
        context.organization_id,
        context.mission_id,
        unrouted,
        context.suffix,
        "SIM-UNROUTED"
      )

    assert {:ok, %{routes: [], findings: [%{code: :missing_downlink_route}]}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               unrouted.spacecraft_id
             )
  end

  test "direct Transports remain local-only and do not gain provider opportunity search",
       context do
    spacecraft =
      persist_spacecraft(context.organization_id, context.mission_id, context.suffix, "direct")

    _mapping =
      persist_mapping(
        context.organization_id,
        context.mission_id,
        spacecraft,
        context.suffix,
        "SIM-DIRECT"
      )

    {:ok, transport} =
      Cadence.persist_transport(
        context.organization_id,
        Transport.new(%{
          mission_id: context.mission_id,
          display_name: "Local lab TCP",
          origin: :direct,
          configuration: %{
            "mode" => "listen",
            "direction_capability" => "inbound",
            "host" => "0.0.0.0",
            "port" => 5200,
            "framing_mode" => "fixed_size",
            "frame_size" => 1115,
            "tls_enabled" => false
          }
        })
      )

    _rule =
      persist_rule!(
        context.organization_id,
        context.mission_id,
        spacecraft,
        transport,
        "#{context.suffix}-direct"
      )

    assert {:ok, %{routes: [], findings: findings}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               spacecraft.spacecraft_id
             )

    assert Enum.any?(findings, &(&1.code == :direct_transport_not_provider_schedulable))
  end

  test "rejects invalid windows and mismatched provider opportunities", context do
    assert {:ok, %{routes: [route]}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               context.spacecraft.spacecraft_id
             )

    starts_at = DateTime.utc_now() |> DateTime.add(120) |> DateTime.truncate(:second)
    ends_at = DateTime.add(starts_at, 3_600)

    window = %{
      "spacecraft_id" => context.spacecraft.spacecraft_id,
      "starts_at" => DateTime.to_iso8601(starts_at),
      "ends_at" => DateTime.to_iso8601(ends_at)
    }

    assert {:error, :invalid_opportunity_window} =
             ProviderScheduling.search_opportunities(
               context.organization_id,
               context.mission_id,
               route.route_key,
               %{window | "ends_at" => window["starts_at"]},
               client: FakeProviderClient
             )

    mismatched = opportunity(route, starts_at) |> Map.put("spacecraft_ref", "OTHER")

    assert {:error, {:invalid_provider_opportunity, "opportunity-alpha"}} =
             ProviderScheduling.search_opportunities(
               context.organization_id,
               context.mission_id,
               route.route_key,
               window,
               client: FakeProviderClient,
               search_response: {:ok, %{"data" => [mismatched]}}
             )
  end

  test "route keys cannot cross organization or mission scope", context do
    assert {:ok, %{routes: [route]}} =
             ProviderScheduling.list_ready_downlink_routes(
               context.organization_id,
               context.mission_id,
               context.spacecraft.spacecraft_id
             )

    assert {:error, :spacecraft_not_found} =
             ProviderScheduling.resolve_ready_downlink_route(
               "another-organization",
               context.mission_id,
               context.spacecraft.spacecraft_id,
               route.route_key
             )
  end

  defp persist_spacecraft(organization_id, mission_id, suffix, name) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-#{suffix}-#{name}",
        mission_id: mission_id,
        display_name: "Spacecraft #{name}"
      })

    {:ok, spacecraft} = Cadence.persist_spacecraft(organization_id, spacecraft)
    spacecraft
  end

  defp persist_mapping(organization_id, mission_id, spacecraft, suffix, source_ref) do
    endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "provider-mapping-#{suffix}-#{spacecraft.spacecraft_id}",
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_ref: source_ref,
        display_name: "#{spacecraft.display_name} provider identity"
      })

    {:ok, endpoint} = Cadence.persist_source_endpoint(organization_id, endpoint)
    endpoint
  end

  defp persist_provider!(organization_id, mission_id, suffix) do
    now = ~U[2026-07-14 12:00:00.000000Z]

    provider =
      MissionProvider.new(%{
        provider_id: "provider-#{suffix}",
        mission_id: mission_id,
        display_name: "Ground Network Simulator",
        provider_type: :simulator,
        base_url: "http://simulator.test",
        credential_ref: "config://simulator",
        environment_ref: "run-alpha",
        last_validated_at: now,
        last_synced_at: now,
        metadata: %{"control_plane" => %{"status" => "healthy"}},
        inventory_sync_document: provider_inventory()
      })

    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end

  defp persist_provider_transport!(organization_id, mission_id, provider, suffix) do
    transport =
      Transport.new(%{
        transport_id: "transport-#{suffix}",
        mission_id: mission_id,
        display_name: "Simulator telemetry ingress",
        origin: :provider_managed,
        mission_provider_id: provider.provider_id,
        mission_provider_version: provider.version,
        service_profile_ref: %{"id" => "service-downlink", "version" => 3},
        delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7}
      })

    {:ok, transport} = Cadence.persist_transport(organization_id, transport)
    transport
  end

  defp persist_rule!(organization_id, mission_id, spacecraft, transport, suffix) do
    rule =
      RoutingRule.new(%{
        routing_rule_id: "routing-rule-#{suffix}",
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Primary telemetry downlink",
        purpose_label: "Telemetry",
        direction: :inbound,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        role: :primary
      })

    {:ok, rule} = Cadence.create_routing_rule(organization_id, rule)
    rule
  end

  defp opportunity(route, starts_at) do
    %{
      "id" => "opportunity-alpha",
      "spacecraft_ref" => route.provider_spacecraft_ref,
      "ground_station_ref" => "station-alpha",
      "antenna_or_service_pool_ref" => "antenna-alpha",
      "service_profile_ref" => route.service_profile_ref["id"],
      "starts_at" => starts_at |> DateTime.add(300) |> DateTime.to_iso8601(),
      "ends_at" => starts_at |> DateTime.add(900) |> DateTime.to_iso8601(),
      "expires_at" => starts_at |> DateTime.add(60) |> DateTime.to_iso8601(),
      "availability" => "available",
      "synthetic" => true,
      "extensions" => %{}
    }
  end

  defp provider_inventory do
    %{
      "service_profiles" => %{
        "items" => [
          %{
            "id" => "service-downlink",
            "version" => 3,
            "display_name" => "Realtime TT&C downlink",
            "direction" => "downlink",
            "state" => "active"
          }
        ]
      },
      "delivery_profiles" => %{
        "items" => [
          %{
            "id" => "delivery-cadence",
            "version" => 7,
            "display_name" => "Cadence primary ingress",
            "direction" => "downlink",
            "delivery_kind" => "realtime_stream",
            "supported_service_profile_refs" => ["service-downlink"],
            "state" => "ready",
            "operator_summary" => "Streaming to Cadence",
            "diagnostics" => %{
              "protocol" => "tcp",
              "mode" => "provider_connects",
              "host" => "127.0.0.1",
              "port" => 5100,
              "framing_family" => "ccsds_tm",
              "frame_bytes" => 1115
            }
          }
        ]
      }
    }
  end
end
