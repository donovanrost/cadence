defmodule Cadence.ProviderAdapters.TCPSocket.Configuration do
  @moduledoc """
  A TCP provider binding's configuration, as the adapter reads it (`normalize/1`): string or atom
  keys, the profile's listener choice (#87), its source allowlist (#990, DECISIONS #115) and its
  quiet-connection threshold (ux U50). Planning reads the listener rules from here too (#361).
  """

  alias Cadence.Comms.PeerAddresses

  # (ux U50) Default for quiet_connection_ms: our own connection read nothing for this long.
  @quiet_connection_ms 30_000

  @doc """
  Whether a provider configuration asks for the profile's shared listener (#87: `listener:
  "shared"`). The runtime's own test (`normalize/1`); planning reads it too (#361).
  """
  @spec shared_listener_config?(map()) :: boolean()
  def shared_listener_config?(configuration) when is_map(configuration),
    do:
      Map.get(configuration, :listener, Map.get(configuration, "listener")) in [:shared, "shared"]

  def shared_listener_config?(_configuration), do: false

  @doc """
  Whether a listen-mode binding on a path of `direction` binds its OWN socket on its host:port,
  so a second contact on the same endpoint at the same time fails `eaddrinuse`
  (`listener_in_use`). Only a shared-listener downlink registers with the profile's acceptor
  instead (`start_socket_provider/3`); uplink always keeps its own listener. Planning's
  listener-overlap flag (#361, U58 (b)) uses this rule, not a copy of it.
  """
  @spec own_listener?(map(), :uplink | :downlink) :: boolean()
  def own_listener?(configuration, direction),
    do: not (direction == :downlink and shared_listener_config?(configuration))

  @doc "The adapter's view of a binding's configuration."
  @spec normalize(map()) :: map()
  def normalize(configuration) when is_map(configuration) do
    mode =
      case Map.get(configuration, :mode, Map.get(configuration, "mode", :connect)) do
        :connect -> :connect
        "connect" -> :connect
        :listen -> :listen
        "listen" -> :listen
      end

    ingress_protocol_family =
      case Map.get(
             configuration,
             :ingress_protocol_family,
             Map.get(configuration, "ingress_protocol_family")
           ) do
        nil ->
          nil

        protocol_family when is_atom(protocol_family) ->
          protocol_family

        protocol_family when is_binary(protocol_family) ->
          String.to_existing_atom(protocol_family)
      end

    %{
      mode: mode,
      host: Map.get(configuration, :host, Map.get(configuration, "host", "127.0.0.1")),
      port: Map.get(configuration, :port, Map.get(configuration, "port", 0)),
      ingress_protocol_family: ingress_protocol_family,
      fixed_message_bytes:
        Map.get(
          configuration,
          :fixed_message_bytes,
          Map.get(configuration, "fixed_message_bytes")
        ) ||
          Map.get(configuration, :frame_size, Map.get(configuration, "frame_size")),
      ingress_transport_binding_id:
        Map.get(
          configuration,
          :ingress_transport_binding_id,
          Map.get(configuration, "ingress_transport_binding_id")
        ),
      source_ref: Map.get(configuration, :source_ref, Map.get(configuration, "source_ref")),
      ingress_metadata:
        Map.get(configuration, :ingress_metadata, Map.get(configuration, "ingress_metadata", %{})),
      # (#87) A listen-mode downlink shares one listener per profile when the profile says
      # "listener" => "shared" (opt-in while profiles are moved over).
      shared_listener?: shared_listener_config?(configuration),
      # (#990, DECISIONS #115) The peers a listening endpoint accepts; a peer outside them is
      # refused before any frame is read.
      allowed_peers:
        configuration
        |> Map.get(:expected_peer_addresses, Map.get(configuration, "expected_peer_addresses"))
        |> PeerAddresses.ranges(),
      # (ux U50) How long our own connection goes without reads before a second connection for
      # this contact counts as a refusal (refuse_second_connection/2).
      quiet_connection_ms:
        configuration
        |> Map.get(
          :quiet_connection_ms,
          Map.get(configuration, "quiet_connection_ms", @quiet_connection_ms)
        )
        |> coerce_integer()
        # A key present with null means the default (api-ops): never fail a contact start on it.
        |> Kernel.||(@quiet_connection_ms)
    }
  end

  defp coerce_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _not_an_integer -> value
    end
  end

  defp coerce_integer(value), do: value
end
