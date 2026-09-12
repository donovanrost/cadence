defmodule Cadence.ContactScheduleFixtures do
  @moduledoc false
  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.{RoutingRule, RoutingRuleStore, Transport}
  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.Management.Transports
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  def setup_schedule do
    suffix = System.unique_integer([:positive])
    org = "org-schedule-#{suffix}"
    mid = "mission-schedule-#{suffix}"

    %{organization: organization, mission: mission} =
      Cadence.DataCase.persist_mission_scope(org, mid)

    spacecraft = persist_spacecraft(org, mid, suffix, "primary")
    persist_mapping(org, mid, spacecraft, suffix, "SIM-001")
    provider = persist_provider!(org, mid, suffix)
    transport = persist_provider_transport!(org, mid, provider, suffix)
    rule = persist_rule!(org, mid, spacecraft, transport, suffix)

    {:ok, %{routes: [route]}} =
      ProviderScheduling.list_ready_downlink_routes(org, mid, spacecraft.spacecraft_id)

    %{
      organization_id: org,
      mission_id: mid,
      mission: mission,
      spacecraft: spacecraft,
      provider: provider,
      transport: transport,
      rule: rule,
      route: route,
      scope: admin_scope(organization, suffix)
    }
  end

  defp persist_spacecraft(organization_id, mission_id, suffix, name) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-#{suffix}-#{name}",
        mission_id: mission_id,
        display_name: "Spacecraft #{name}"
      })

    {:ok, spacecraft} = Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)
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

    {:ok, endpoint} = Cadence.SourceEndpoints.persist_source_endpoint(organization_id, endpoint)
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

    {:ok, transport} = Transports.persist_transport(organization_id, transport)
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

    {:ok, rule} = RoutingRuleStore.create_routing_rule(organization_id, rule)
    rule
  end

  def opportunity(route, starts_at) do
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

  defp admin_scope(organization, suffix) do
    user =
      User.new(%{
        user_id: "user-provider-change-#{suffix}",
        email: "provider-change-#{suffix}@example.test",
        display_name: "Provider Change Admin"
      })

    membership =
      OrganizationMembership.new(%{
        organization_membership_id: "membership-provider-change-#{suffix}",
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: :organization_admin
      })

    Scope.new(%{
      user: user,
      organization: organization,
      organization_id: organization.organization_id,
      organization_membership: membership
    })
  end
end
