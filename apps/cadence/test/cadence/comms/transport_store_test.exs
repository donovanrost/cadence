defmodule Cadence.Comms.TransportStoreTest do
  use Cadence.DataCase, async: true

  alias Cadence.Comms.Transport
  alias Cadence.Comms.TransportKinds.TCPSocket

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
  end

  describe "persist_transport/2 and queries" do
    test "persists, fetches, lists, versions, and materializes provider compatibility" do
      persist_mission_scope("org-transport", "mission-transport")

      transport =
        Transport.new(%{
          mission_id: "mission-transport",
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

      assert {:ok, persisted_v1} = Cadence.persist_transport("org-transport", transport)
      assert persisted_v1.organization_id == "org-transport"
      assert persisted_v1.version == 1
      assert persisted_v1.direction_capability == :inbound
      assert is_binary(persisted_v1.materialized_provider_profile_id)

      assert {:ok, provider} =
               Cadence.fetch_provider_profile(
                 "org-transport",
                 "mission-transport",
                 persisted_v1.materialized_provider_profile_id
               )

      assert provider.configuration["direction"] == "downlink"
      assert provider.metadata["materialized_from_transport_id"] == persisted_v1.transport_id

      assert {:ok, latest} =
               Cadence.fetch_transport(
                 "org-transport",
                 "mission-transport",
                 persisted_v1.transport_id
               )

      assert latest.version == 1

      assert {:ok, persisted_v2} =
               Cadence.version_transport(
                 "org-transport",
                 "mission-transport",
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

      assert [listed] = Cadence.list_transports("org-transport", "mission-transport")
      assert listed.version == 2

      assert [v2, v1] =
               Cadence.list_transport_versions(
                 "org-transport",
                 "mission-transport",
                 persisted_v1.transport_id
               )

      assert v1.version == 1
      assert v2.version == 2
    end
  end
end
