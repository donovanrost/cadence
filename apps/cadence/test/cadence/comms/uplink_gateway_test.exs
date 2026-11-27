defmodule Cadence.Comms.UplinkGatewayTest do
  use Cadence.DataCase, async: false

  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport}
  alias Cadence.Contacts.{PathTemplateStore, UplinkLegs}
  alias Cadence.GroundNetworks.{MissionProvider, MissionProviders}
  alias Cadence.Management.Transports
  alias Cadence.Spacecraft

  setup do
    suffix = System.unique_integer([:positive])
    org = "org-uplink-#{suffix}"
    mission = "mission-uplink-#{suffix}"
    Cadence.DataCase.persist_mission_scope(org, mission)
    {:ok, provider} = MissionProviders.persist_provider(org, provider(mission, suffix))

    {:ok, craft} =
      Cadence.SpacecraftStore.persist_spacecraft(
        org,
        Spacecraft.new(%{
          spacecraft_id: "craft-#{suffix}",
          mission_id: mission,
          display_name: "Craft",
          scid: 42
        })
      )

    %{org: org, mission: mission, provider: provider, craft: craft, suffix: suffix}
  end

  test "an uplink delivery becomes an outbound listener for CLCWs", c do
    assert {:ok, transport} = uplink_transport(c)

    assert %Transport{direction_capability: :outbound, configuration: config} = transport

    assert %{
             "mode" => "listen",
             "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
             "ingress_protocol_family" => "cop1_clcw",
             "port" => 5200
           } =
             config

    assert config["fixed_message_bytes"] == 4
  end

  test "an outbound route releases through a per-spacecraft gateway linked to the listener", c do
    {:ok, transport} = uplink_transport(c)
    {:ok, rule} = outbound_rule(c, transport)

    [template_id] = rule.metadata["materialized_path_template_ids"]
    {:ok, template} = PathTemplateStore.fetch(c.org, c.mission, template_id)
    assert template.direction == :uplink
    assert {:ok, path} = PathTemplateStore.resolve(template)

    assert [gateway] = path.transport_bindings
    assert gateway.family_key == :uplink_gateway

    assert %{"scid" => 42, "frame_size" => 32, "cop1_mode" => "fop"} = gateway.configuration
    assert [listener] = path.provider_bindings
    assert gateway.configuration["provider_binding_id"] == listener.provider_binding_id
    assert listener.configuration["ingress_transport_binding_id"] == gateway.transport_binding_id
  end

  test "a booking at the primary uplink station requests the uplink leg", c do
    {:ok, transport} = uplink_transport(c)
    {:ok, _rule} = outbound_rule(c, transport)

    assert %{
             "service_profile_ref" => %{"id" => "service-uplink"},
             "delivery_profile_ref" => %{"id" => "delivery-uplink"},
             "path_template_id" => template_id
           } =
             UplinkLegs.for_booking(
               c.org,
               c.mission,
               c.craft.spacecraft_id,
               "station-svb",
               c.provider.provider_id
             )

    assert is_binary(template_id)

    assert UplinkLegs.for_booking(
             c.org,
             c.mission,
             c.craft.spacecraft_id,
             "station-elsewhere",
             c.provider.provider_id
           ) == nil
  end

  test "a downlink service can't pair with an uplink delivery", c do
    assert {:error, :provider_profile_direction_not_supported} =
             uplink_transport(c, %{"id" => "service-downlink", "version" => 1})
  end

  defp outbound_rule(c, transport) do
    RoutingRuleStore.create_routing_rule(
      c.org,
      RoutingRule.new(%{
        mission_id: c.mission,
        spacecraft_id: c.craft.spacecraft_id,
        display_name: "Svalbard uplink",
        purpose_label: "TT&C uplink",
        direction: :outbound,
        role: :primary,
        transport_id: transport.transport_id,
        transport_version: transport.version
      })
    )
  end

  defp uplink_transport(c, service_ref \\ %{"id" => "service-uplink", "version" => 1}) do
    Transports.persist_transport(
      c.org,
      Transport.new(%{
        transport_id: "transport-uplink-#{c.suffix}",
        mission_id: c.mission,
        display_name: "Svalbard uplink",
        ground_station_id: "station-svb",
        origin: :provider_managed,
        mission_provider_id: c.provider.provider_id,
        mission_provider_version: c.provider.version,
        service_profile_ref: service_ref,
        delivery_profile_ref: %{"id" => "delivery-uplink", "version" => 1}
      })
    )
  end

  defp provider(mission, suffix) do
    MissionProvider.new(%{
      provider_id: "provider-uplink-#{suffix}",
      mission_id: mission,
      display_name: "Simulator",
      provider_type: :simulator,
      base_url: "http://simulator.test",
      credential_ref: "config://simulator",
      environment_ref: "run-uplink-#{suffix}",
      last_validated_at: ~U[2026-07-15 12:00:00.000000Z],
      last_synced_at: ~U[2026-07-15 12:00:00.000000Z],
      metadata: %{"control_plane" => %{"status" => "healthy"}},
      inventory_sync_document: %{
        "service_profiles" => %{
          "items" => [
            service("service-downlink", "downlink"),
            service("service-uplink", "uplink")
          ]
        },
        "delivery_profiles" => %{
          "items" => [
            %{
              "id" => "delivery-uplink",
              "version" => 1,
              "display_name" => "Cadence uplink",
              "direction" => "uplink",
              "delivery_kind" => "realtime_stream",
              "supported_service_profile_refs" => ["service-uplink", "service-downlink"],
              "state" => "ready",
              "egress" => %{"source_addresses" => ["127.0.0.1/32", "::1/128"]},
              "diagnostics" => %{
                "protocol" => "tcp",
                "mode" => "provider_connects",
                "host" => "127.0.0.1",
                "port" => 5200,
                "framing_family" => "ccsds_tc",
                "frame_bytes" => 32
              }
            }
          ]
        }
      }
    })
  end

  defp service(id, direction),
    do: %{
      "id" => id,
      "version" => 1,
      "display_name" => id,
      "direction" => direction,
      "state" => "active"
    }
end
