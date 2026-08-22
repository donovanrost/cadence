defmodule Cadence.Comms.TransportStoreTest do
  use Cadence.DataCase, async: false

  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.{Transport, TransportKind}
  alias Cadence.Comms.TransportKind.Definition
  alias Cadence.Comms.TransportKinds.TCPSocket
  alias Cadence.Extensions.Presentation.ConfigurationDefinition
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.MissionProvider
  alias Cadence.Management.Transports

  describe "TCP transport kind" do
    test "normalizes and summarizes TCP config" do
      assert {:ok, config} =
               TCPSocket.normalize_config(%{
                 "mode" => "connect",
                 "direction_capability" => "outbound",
                 "host" => "ground.example",
                 "port" => "5000",
                 "framing_mode" => "fixed_size",
                 "frame_size" => "64",
                 "reconnect_policy" => "always",
                 "tls_enabled" => "true"
               })

      assert config["direction_capability"] == "outbound"
      assert config["port"] == 5000
      assert config["fixed_message_bytes"] == 64
      assert config["framing"] == %{"mode" => "fixed_size", "fixed_message_bytes" => 64}
      assert config["reconnect"] == %{"policy" => "always"}
      assert config["tls"] == %{"enabled" => true}

      assert TCPSocket.display_summary(config) == %{
               endpoint: "ground.example:5000",
               mode: "connect",
               direction_capability: "outbound",
               framing: "fixed_size",
               tls_enabled?: true
             }
    end

    test "rejects invalid TCP ports" do
      assert {:error, "Port must be an integer from 1 to 65535."} =
               TCPSocket.normalize_config(%{
                 "mode" => "listen",
                 "direction_capability" => "inbound",
                 "host" => "0.0.0.0",
                 "port" => "70000",
                 "framing_mode" => "raw",
                 "tls_enabled" => "false"
               })
    end

    test "resolves allow-listed form values through transport kind metadata" do
      assert [{"TCP socket", "tcp_socket"}] = TransportKind.form_options()

      assert {:ok, entry} = TransportKind.resolve_form_value("tcp_socket")
      assert entry.version == 1
      assert entry.kind == :tcp_socket
      assert entry.adapter_key == :tcp_socket
      assert entry.module == TCPSocket
      assert %ConfigurationDefinition{} = entry.configuration

      assert Enum.map(entry.configuration.sections, & &1.id) == [
               "transport-capability-section",
               "transport-framing-section",
               "transport-reliability-section"
             ]

      assert ConfigurationDefinition.default_params(entry.configuration)["tcp_mode"] ==
               "listen"

      assert :ok = Definition.validate(entry)

      assert {:error, :unsupported_transport_kind_version} =
               TransportKind.resolve_form_value("tcp_socket", 2)

      assert {:error, :unsupported_transport_kind} =
               TransportKind.resolve_form_value("invented")
    end
  end

  describe "persist_transport/2 and queries" do
    test "persists, fetches, lists, versions, and materializes provider compatibility" do
      suffix = Integer.to_string(System.unique_integer([:positive]))
      organization_id = "org-transport-" <> suffix
      mission_id = "mission-transport-" <> suffix

      persist_mission_scope(organization_id, mission_id)

      transport =
        Transport.new(%{
          mission_id: mission_id,
          display_name: "Lab TCP",
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

      assert {:ok, persisted_v1} =
               TransportStore.persist_transport(organization_id, transport)

      assert persisted_v1.organization_id == organization_id
      assert persisted_v1.version == 1
      assert persisted_v1.origin == :direct
      assert persisted_v1.direction_capability == :inbound
      assert persisted_v1.mission_provider_id == nil
      assert is_binary(persisted_v1.materialized_provider_profile_id)

      assert {:ok, provider} =
               Cadence.Contacts.fetch_provider_profile(
                 organization_id,
                 mission_id,
                 persisted_v1.materialized_provider_profile_id
               )

      assert provider.configuration["direction"] == "downlink"
      assert provider.metadata["materialized_from_transport_id"] == persisted_v1.transport_id

      assert {:ok, latest} =
               TransportStore.fetch_transport(
                 organization_id,
                 mission_id,
                 persisted_v1.transport_id
               )

      assert latest.version == 1

      assert {:ok, persisted_v2} =
               TransportStore.version_transport(
                 organization_id,
                 mission_id,
                 persisted_v1.transport_id,
                 %{
                   display_name: "Lab TCP",
                   direction_capability: :bidirectional,
                   configuration: %{
                     "mode" => "connect",
                     "direction_capability" => "bidirectional",
                     "host" => "ground.example",
                     "port" => "6000",
                     "framing_mode" => "line_delimited",
                     "reconnect_policy" => "always",
                     "tls_enabled" => "true"
                   }
                 }
               )

      assert persisted_v2.version == 2
      assert persisted_v2.direction_capability == :bidirectional

      refute persisted_v2.materialized_provider_profile_id ==
               persisted_v1.materialized_provider_profile_id

      assert [listed] = TransportStore.list_transports(organization_id, mission_id)
      assert listed.version == 2

      assert [v2, v1] =
               TransportStore.list_transport_versions(
                 organization_id,
                 mission_id,
                 persisted_v1.transport_id
               )

      assert v1.version == 1
      assert v2.version == 2
    end

    test "derives and snapshots provider-managed TCP setup from exact profile versions" do
      suffix = Integer.to_string(System.unique_integer([:positive]))
      organization_id = "org-provider-transport-" <> suffix
      mission_id = "mission-provider-transport-" <> suffix

      persist_mission_scope(organization_id, mission_id)
      provider = persist_ready_provider!(organization_id, mission_id)

      transport =
        Transport.new(%{
          mission_id: mission_id,
          display_name: "Provider Downlink",
          origin: :provider_managed,
          transport_kind: :tcp_socket,
          direction_capability: :inbound,
          adapter_key: :tcp_socket,
          configuration: %{"host" => "must-not-win", "port" => 1},
          mission_provider_id: provider.provider_id,
          mission_provider_version: provider.version,
          service_profile_ref: %{"id" => "service-downlink", "version" => 3},
          delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7}
        })

      assert {:error, :provider_transport_basis_required} =
               TransportStore.persist_transport(organization_id, transport)

      assert {:ok, persisted} = Transports.persist_transport(organization_id, transport)

      assert persisted.origin == :provider_managed
      assert persisted.transport_kind == :tcp_socket
      assert persisted.adapter_key == :tcp_socket
      assert persisted.direction_capability == :inbound
      assert persisted.mission_provider_id == provider.provider_id
      assert persisted.mission_provider_version == provider.version
      assert persisted.service_profile_ref == %{"id" => "service-downlink", "version" => 3}
      assert persisted.delivery_profile_ref == %{"id" => "delivery-cadence", "version" => 7}
      assert persisted.configuration["host"] == "127.0.0.1"
      assert persisted.configuration["port"] == 5100
      assert persisted.configuration["fixed_message_bytes"] == 1115
      assert persisted.configuration["ingress_protocol_family"] == "tm"

      assert persisted.configuration["ingress_metadata"] == %{
               "frame_size" => 1115,
               "ocf_length" => 0
             }

      assert get_in(persisted.provider_configuration_snapshot, ["provider", "display_name"]) ==
               "Simulator"

      assert get_in(persisted.provider_configuration_snapshot, [
               "delivery_profile",
               "diagnostics",
               "api_token"
             ]) == "[REDACTED]"

      assert {:ok, runtime_profile} =
               Cadence.Contacts.fetch_provider_profile(
                 organization_id,
                 mission_id,
                 persisted.materialized_provider_profile_id
               )

      assert runtime_profile.configuration["host"] == "127.0.0.1"
      assert runtime_profile.configuration["direction"] == "downlink"
      assert runtime_profile.configuration["ingress_protocol_family"] == "tm"
      assert runtime_profile.metadata["transport_origin"] == "provider_managed"
      assert runtime_profile.metadata["mission_provider_id"] == provider.provider_id

      assert runtime_profile.metadata["service_profile_ref"] == %{
               "id" => "service-downlink",
               "version" => 3
             }
    end

    test "rejects provider-managed transports until provider validation and sync are healthy" do
      suffix = Integer.to_string(System.unique_integer([:positive]))
      organization_id = "org-unready-provider-transport-" <> suffix
      mission_id = "mission-unready-provider-transport-" <> suffix

      persist_mission_scope(organization_id, mission_id)

      provider =
        MissionProvider.new(%{
          mission_id: mission_id,
          display_name: "Unvalidated Simulator",
          provider_type: :simulator,
          base_url: "http://127.0.0.1:4101",
          credential_ref: "config://simulator",
          environment_ref: "local"
        })

      assert {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)

      transport =
        Transport.new(%{
          mission_id: mission_id,
          display_name: "Premature Downlink",
          origin: :provider_managed,
          mission_provider_id: provider.provider_id,
          mission_provider_version: provider.version,
          service_profile_ref: %{"id" => "service-downlink", "version" => 3},
          delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 7}
        })

      assert {:error, :mission_provider_not_validated} =
               Transports.persist_transport(organization_id, transport)
    end
  end

  defp persist_ready_provider!(organization_id, mission_id) do
    now = ~U[2026-07-14 12:00:00.000000Z]

    provider =
      MissionProvider.new(%{
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
      })

    {:ok, provider} = GroundNetworks.persist_provider(organization_id, provider)
    provider
  end
end
