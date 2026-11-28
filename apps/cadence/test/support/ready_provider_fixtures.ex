defmodule Cadence.ReadyProviderFixtures do
  @moduledoc """
  A mission provider that is validated, synced and healthy, with one active downlink service
  profile (`service-downlink` v3) and one ready delivery profile (`delivery-cadence` v7) that
  supports it: enough to derive a provider-managed TCP transport.
  """

  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider

  def persist_ready_provider!(organization_id, mission_id, attrs \\ %{}) do
    now = ~U[2026-07-14 12:00:00.000000Z]

    provider =
      %{
        mission_id: mission_id,
        display_name: "Simulator",
        provider_type: :simulator,
        base_url: "http://127.0.0.1:4101",
        credential_ref: "config://simulator",
        environment_ref: "local",
        last_validated_at: now,
        last_synced_at: now,
        metadata: %{"control_plane" => %{"status" => "healthy"}},
        capabilities_document: %{"operations" => %{"inventory_discovery" => true}},
        inventory_sync_document: %{
          "service_profiles" => %{
            "items" => [
              %{
                "id" => "service-downlink",
                "version" => 3,
                "display_name" => "Realtime telemetry",
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
                "egress" => %{"source_addresses" => ["127.0.0.1/32", "::1/128"]},
                "diagnostics" => %{
                  "protocol" => "tcp",
                  "mode" => "provider_connects",
                  "host" => "127.0.0.1",
                  "port" => 5100,
                  "framing_family" => "ccsds_tm",
                  "frame_bytes" => 1115,
                  "endpoint_health" => "healthy",
                  "api_token" => "must-not-persist"
                }
              }
            ]
          }
        }
      }
      |> Map.merge(attrs)
      |> MissionProvider.new()

    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end
end
