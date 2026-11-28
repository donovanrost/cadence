defmodule Cadence.Comms.TransportStoreTest do
  use Cadence.DataCase, async: false

  import Cadence.ReadyProviderFixtures

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.{Transport, TransportKind, TransportRow}
  alias Cadence.Comms.TransportKind.Definition
  alias Cadence.Comms.TransportKinds.TCPSocket
  alias Cadence.Extensions.Presentation.ConfigurationDefinition
  alias Cadence.GroundNetworks
  alias Cadence.GroundNetworks.{MissionProvider, ProviderAudit}
  alias Cadence.Management.Transports
  alias Cadence.Persistence.JsonDocument

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
                 "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
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
            "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
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
          configuration: %{"host" => "must-not-win", "port" => 1, "listener" => "shared"},
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
      assert persisted.configuration["listener"] == "shared"

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
      assert runtime_profile.configuration["listener"] == "shared"
      assert runtime_profile.metadata["transport_origin"] == "provider_managed"
      assert runtime_profile.metadata["mission_provider_id"] == provider.provider_id

      assert runtime_profile.metadata["service_profile_ref"] == %{
               "id" => "service-downlink",
               "version" => 3
             }
    end

    test "a direct transport cannot claim a provider-managed delivery credential" do
      org = "org-mtls-listen"
      mission = "mission-mtls-listen"
      persist_mission_scope(org, mission)

      transport =
        Transport.new(%{
          mission_id: mission,
          display_name: "Mutual TLS downlink",
          configuration: %{
            "mode" => "listen",
            "direction_capability" => "inbound",
            "host" => "127.0.0.1",
            "port" => 5100,
            "framing_mode" => "raw",
            "expected_peer_addresses" => ["127.0.0.1/32"],
            "delivery_auth" => "mtls"
          }
        })

      assert {:error, :delivery_binding_unavailable} =
               TransportStore.persist_transport(org, transport)
    end

    test "only an explicit audited downgrade can replace mTLS with an allowlisted profile" do
      org = "org-delivery-downgrade"
      mission = "mission-delivery-downgrade"
      persist_mission_scope(org, mission)
      provider = persist_ready_provider!(org, mission)
      delivery_ref = %{"id" => "delivery-cadence", "version" => 7}

      transport =
        Transport.new(%{
          mission_id: mission,
          display_name: "Provider downlink",
          origin: :provider_managed,
          mission_provider_id: provider.provider_id,
          mission_provider_version: provider.version,
          service_profile_ref: %{"id" => "service-downlink", "version" => 3},
          delivery_profile_ref: delivery_ref
        })

      assert {:ok, current} = Transports.persist_transport(org, transport)
      binding = current.transport_id

      # Exercise protection of an mTLS transport before this slice can create its listener.
      config = Map.put(current.configuration, "delivery_auth", "mtls")

      assert {1, _} =
               Repo.update_all(
                 from(row in TransportRow,
                   where: row.organization_id == ^org and row.transport_id == ^binding
                 ),
                 set: [configuration: JsonDocument.wrap_value(config)]
               )

      assert {:error, :delivery_auth_downgrade_required} =
               Transports.version_transport(org, mission, binding, %{
                 origin: :provider_managed,
                 mission_provider_id: provider.provider_id,
                 delivery_profile_ref: delivery_ref
               })

      admin_user =
        User.new(%{
          user_id: "admin-delivery-downgrade",
          display_name: "Delivery Admin",
          email: "delivery-admin@example.test"
        })

      admin =
        Scope.new(%{
          user: admin_user,
          organization_id: org,
          organization_membership:
            OrganizationMembership.new(%{
              organization_id: org,
              user_id: admin_user.user_id,
              role: :organization_admin
            })
        })

      params = %{
        "expected_version" => 1,
        "reason" => "provider_compatibility",
        "delivery_profile_ref" => delivery_ref
      }

      assert {:error, :version_conflict} =
               Transports.downgrade_delivery_auth(
                 admin,
                 mission,
                 provider.provider_id,
                 binding,
                 %{params | "expected_version" => 2}
               )

      assert {:ok, updated} =
               Transports.downgrade_delivery_auth(
                 admin,
                 mission,
                 provider.provider_id,
                 binding,
                 params
               )

      assert updated.version == 2
      assert updated.configuration["expected_peer_addresses"] == ["127.0.0.1/32", "::1/128"]

      assert [entry] =
               ProviderAudit.list_entries(org,
                 mission_id: mission,
                 actions: ["provider_delivery_credential.downgrade"]
               )

      assert entry.actor_document["id"] == "admin-delivery-downgrade"
      assert entry.decision_document["reason"] == "provider_compatibility"
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
end
