defmodule Cadence.Comms.ListenClaimsTest do
  @moduledoc """
  SAFETY (multi-tenant isolation): a listen host:port is ONE mission's. Another mission's listen
  profile or transport on it is refused at save and at contact start (fail closed); the same
  mission may reuse it (a station pair sharing a port by design).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Comms.ConfigKinds.Transport, as: TransportKind
  alias Cadence.Comms.{ListenClaims, Transport, TransportStore}

  alias Cadence.Contacts.{
    ContactStartFailure,
    Path,
    ProfileStore,
    ProviderBinding,
    ProviderProfile,
    RealizedContact
  }

  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Reads.ActionQueue.ContactStartItem

  setup do
    suffix = System.unique_integer([:positive])
    # A port no other test uses, so this test's advisory locks hold no one else up.
    port = 20_000 + rem(suffix, 20_000)

    scopes =
      for {org, mission} <- [
            {"org-listen-a-#{suffix}", "mission-listen-a-#{suffix}"},
            {"org-listen-a-#{suffix}", "mission-listen-b-#{suffix}"},
            {"org-listen-c-#{suffix}", "mission-listen-c-#{suffix}"}
          ] do
        persist_mission_scope(org, mission)
        %{organization_id: org, mission_id: mission}
      end

    [a, b, c] = scopes
    %{port: port, a: a, b: b, c: c, suffix: suffix}
  end

  describe "saving a provider profile" do
    test "another mission's listener on the same host:port is refused", %{a: a, b: b, port: port} do
      assert {:ok, _profile} = persist_profile(a, "rx-a", listen("127.0.0.1", port))

      assert {:error, {:listen_endpoint_claimed, %{host: "127.0.0.1", port: ^port}}} =
               persist_profile(b, "rx-b", listen("127.0.0.1", port))

      assert {:error, :contact_provider_profile_not_found} =
               ProfileStore.fetch_provider_profile(b.organization_id, b.mission_id, "rx-b")
    end

    test "the same mission may reuse its host:port", %{a: a, port: port} do
      assert {:ok, _first} = persist_profile(a, "rx-a-1", listen("127.0.0.1", port))
      assert {:ok, _second} = persist_profile(a, "rx-a-2", listen("127.0.0.1", port))
    end

    test "a claim spans organizations, and the refusal names no mission", %{
      a: a,
      c: c,
      port: port
    } do
      assert {:ok, _profile} = persist_profile(a, "rx-a", listen("127.0.0.1", port))

      assert {:error, {:listen_endpoint_claimed, endpoint}} =
               persist_profile(c, "rx-c", listen("localhost", port))

      assert endpoint == %{host: "127.0.0.1", port: port}
      refute ListenClaims.message() =~ a.mission_id
    end

    test "a wildcard bind overlaps every host on its port", %{a: a, b: b, port: port} do
      assert {:ok, _profile} = persist_profile(a, "rx-a", listen("0.0.0.0", port))

      assert {:error, {:listen_endpoint_claimed, _endpoint}} =
               persist_profile(b, "rx-b", listen("10.0.0.5", port))
    end

    test "another port, a connect profile or an OS-chosen port claims nothing", %{
      a: a,
      b: b,
      port: port
    } do
      assert {:ok, _profile} = persist_profile(a, "rx-a", listen("127.0.0.1", port))
      assert {:ok, _other_port} = persist_profile(b, "rx-b", listen("127.0.0.1", port + 1))

      assert {:ok, _connect} =
               persist_profile(b, "tx-b", %{"mode" => "connect", "host" => "h", "port" => port})

      assert {:ok, _zero} = persist_profile(b, "rx-b-0", listen("127.0.0.1", 0))
    end

    test "a deleted profile releases its claim; a profile moved off the port does too", %{
      a: a,
      b: b,
      port: port
    } do
      assert {:ok, _profile} = persist_profile(a, "rx-a", listen("127.0.0.1", port))
      assert {:ok, _moved} = persist_profile(a, "rx-a2", listen("127.0.0.1", port))

      assert {:ok, _deleted} =
               ProfileStore.delete_provider_profile(a.organization_id, a.mission_id, "rx-a")

      assert {:ok, _versioned} =
               ProfileStore.version_provider_profile(a.organization_id, a.mission_id, "rx-a2", %{
                 configuration: listen("127.0.0.1", port + 1)
               })

      assert {:ok, _profile} = persist_profile(b, "rx-b", listen("127.0.0.1", port))
    end
  end

  describe "saving a transport" do
    test "another mission's transport on the same host:port is refused; its own isn't", %{
      a: a,
      b: b,
      port: port
    } do
      assert {:ok, _transport} = persist_transport(a, port)
      assert {:ok, _same_mission} = persist_transport(a, port)

      assert {:error, {:listen_endpoint_claimed, %{port: ^port}}} = persist_transport(b, port)
      assert TransportStore.list_transports(b.organization_id, b.mission_id) == []
    end

    test "the change-set kind reports it on the port field before staging", %{
      a: a,
      b: b,
      port: port
    } do
      assert {:ok, _transport} = persist_transport(a, port)

      document = %{
        "origin" => "direct",
        "display_name" => "Lab TCP",
        "transport_kind" => "tcp_socket",
        "configuration" => tcp_config(port)
      }

      assert {:error, [%{path: "configuration.port", message: message}]} =
               TransportKind.validate(
                 b.organization_id,
                 b.mission_id,
                 :create,
                 nil,
                 nil,
                 document
               )

      assert message == ListenClaims.message()

      assert :ok =
               TransportKind.validate(
                 a.organization_id,
                 a.mission_id,
                 :create,
                 nil,
                 nil,
                 document
               )
    end

    test "the store's refusal at write reads the same, on the port field (ux U81)", %{
      a: a,
      b: b,
      port: port
    } do
      assert {:ok, _transport} = persist_transport(a, port)

      document = %{
        "origin" => "direct",
        "display_name" => "Lab TCP",
        "transport_kind" => "tcp_socket",
        "direction_capability" => "inbound",
        "configuration" => tcp_config(port)
      }

      # As when validate passed before another mission's save took the port.
      assert {:error, [%{path: "configuration.port", message: message}]} =
               TransportKind.write(
                 b.organization_id,
                 b.mission_id,
                 :create,
                 "transport-listen-b",
                 nil,
                 document,
                 []
               )

      assert message == ListenClaims.message()
    end
  end

  describe "starting a contact" do
    test "a pass whose pinned listener another mission claims doesn't start", %{
      a: a,
      b: b,
      port: port
    } do
      assert {:ok, _profile} = persist_profile(a, "rx-a", listen("127.0.0.1", port))

      contact = %RealizedContact{
        organization_id: b.organization_id,
        mission_id: b.mission_id,
        realized_contact_id: "realized-listen-b",
        paths: [
          %Path{
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: "binding-listen-b",
                adapter_key: :tcp_socket,
                configuration: listen("127.0.0.1", port),
                metadata: %{
                  "display_name" => "INU S-band",
                  "materialized_from_transport_id" => "transport-inu"
                }
              })
            ]
          }
        ]
      }

      assert {:error, {:listen_endpoint_claimed, claim} = error} =
               ControlContacts.start_realized_contact(contact)

      assert claim == %{
               host: "127.0.0.1",
               port: port,
               provider_binding_id: "binding-listen-b",
               transport_id: "transport-inu",
               transport_name: "INU S-band"
             }

      assert :ok = ListenClaims.check_paths(a.mission_id, contact.paths)

      # The start failure the Now item reads (ux U81: "Didn't start: another mission listens on
      # the port INU S-band uses (port). Change that transport's port.").
      assert %{"start_failure" => failure} =
               ContactStartFailure.failed(contact, error, DateTime.utc_now())

      assert failure["reason"] == "listen_endpoint_claimed"
      assert failure["reason"] in ContactStartFailure.reasons()
      assert failure["provider_binding_id"] == "binding-listen-b"
      assert failure["listen_port"] == port
      assert failure["transport_id"] == "transport-inu"
      assert failure["transport_name"] == "INU S-band"

      # On the wire (fe-ops' reader): the Now item's contact_start fields.
      wire =
        ContactStartItem.fields(
          %{
            reason: failure["reason"],
            listen_port: failure["listen_port"],
            transport_id: failure["transport_id"],
            transport_name: failure["transport_name"]
          },
          %{},
          fn _ref -> nil end
        )

      assert %{
               reason: "listen_endpoint_claimed",
               listen_port: ^port,
               transport_id: "transport-inu",
               transport_name: "INU S-band"
             } = wire
    end
  end

  defp listen(host, port), do: %{"mode" => "listen", "host" => host, "port" => port}

  defp persist_profile(scope, id, configuration) do
    ProfileStore.persist_provider_profile(
      scope.organization_id,
      ProviderProfile.new(%{
        provider_profile_id: id,
        mission_id: scope.mission_id,
        adapter_key: :tcp_socket,
        configuration: configuration
      })
    )
  end

  defp tcp_config(port) do
    %{
      "mode" => "listen",
      "direction_capability" => "inbound",
      "host" => "127.0.0.1",
      "port" => Integer.to_string(port),
      "framing_mode" => "raw",
      "tls_enabled" => "false"
    }
  end

  defp persist_transport(scope, port) do
    TransportStore.persist_transport(
      scope.organization_id,
      Transport.new(%{
        mission_id: scope.mission_id,
        display_name: "Lab TCP",
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: tcp_config(port)
      })
    )
  end
end
