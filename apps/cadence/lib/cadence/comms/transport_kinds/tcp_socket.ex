defmodule Cadence.Comms.TransportKinds.TCPSocket do
  @moduledoc """
  TCP socket transport kind.

  The configuration is durable setup for a TCP byte-moving capability, not an
  active connection. Runtime provider profile materialization is a compatibility
  bridge for existing contact/runtime code.
  """

  @behaviour Cadence.Comms.TransportKind

  import Cadence.Comms.TransportKinds.TCPSocket.Fields

  alias Cadence.Comms.{PeerAddresses, Transport}
  alias Cadence.Comms.TransportKind.Definition
  alias Cadence.Contacts.ProviderProfile

  alias Cadence.Extensions.Presentation.{
    ConfigurationDefinition,
    FieldDefinition,
    SectionDefinition
  }

  @config_atom_keys %{
    "direction" => :direction,
    "direction_capability" => :direction_capability,
    "delivery_auth" => :delivery_auth,
    "delivery_credential_ref" => :delivery_credential_ref,
    "delivery_kind" => :delivery_kind,
    "diagnostics" => :diagnostics,
    "egress" => :egress,
    "enabled" => :enabled,
    "expected_peer_addresses" => :expected_peer_addresses,
    "frame_bytes" => :frame_bytes,
    "fixed_message_bytes" => :fixed_message_bytes,
    "frame_size" => :frame_size,
    "framing" => :framing,
    "framing_family" => :framing_family,
    "framing_mode" => :framing_mode,
    "host" => :host,
    "ingress_metadata" => :ingress_metadata,
    "ingress_protocol_family" => :ingress_protocol_family,
    "listener" => :listener,
    "mode" => :mode,
    "policy" => :policy,
    "port" => :port,
    "protocol" => :protocol,
    "source_addresses" => :source_addresses,
    "reconnect" => :reconnect,
    "reconnect_policy" => :reconnect_policy,
    "state" => :state,
    "tls" => :tls,
    "tls_enabled" => :tls_enabled,
    "uplink_resource_id" => :uplink_resource_id
  }

  @impl true
  def definition do
    %Definition{
      form_value: "tcp_socket",
      version: 1,
      kind: :tcp_socket,
      adapter_key: :tcp_socket,
      label: "TCP socket",
      description: "Move framed or raw bytes over a directly managed TCP endpoint.",
      module: __MODULE__,
      configuration: %ConfigurationDefinition{
        id: "transport-direct-configuration",
        description: "Cadence owns this endpoint, framing boundary, and reconnect behavior.",
        sections: [
          %SectionDefinition{
            id: "transport-capability-section",
            number: "04",
            title: "TCP Capability",
            fields: [
              %FieldDefinition{
                field: :tcp_mode,
                label: "TCP Mode",
                type: :select,
                required: true,
                default: "listen",
                options: [
                  {"TCP server (listen)", "listen"},
                  {"TCP client (connect)", "connect"}
                ]
              },
              %FieldDefinition{
                field: :direction_capability,
                label: "Direction Capability",
                type: :select,
                required: true,
                default: "inbound",
                options: [
                  {"Inbound", "inbound"},
                  {"Outbound", "outbound"},
                  {"Bidirectional", "bidirectional"}
                ]
              },
              %FieldDefinition{
                field: :host,
                label: "Host or bind interface",
                type: :text,
                required: true,
                default: "0.0.0.0",
                placeholder: "0.0.0.0"
              },
              %FieldDefinition{
                field: :port,
                label: "TCP Port",
                type: :number,
                required: true,
                min: 1,
                max: 65_535
              },
              # #990 (DECISIONS #115): a listening endpoint only accepts these peers.
              %FieldDefinition{
                field: :expected_peer_addresses,
                label: "Allowed source addresses",
                type: :text,
                required: true,
                placeholder: "203.0.113.10, 198.51.100.0/24",
                help:
                  "The IP addresses or CIDR ranges the provider connects from, separated by " <>
                    "commas. Any other peer is refused before Cadence reads from it.",
                visible_when: %{field: :tcp_mode, equals: "listen"}
              }
            ]
          },
          %SectionDefinition{
            id: "transport-framing-section",
            number: "05",
            title: "Framing",
            fields: [
              %FieldDefinition{
                field: :framing_mode,
                label: "Framing",
                type: :select,
                required: true,
                default: "raw",
                options: [
                  {"Raw bytes", "raw"},
                  {"Fixed-size frames", "fixed_size"},
                  {"Line-delimited", "line_delimited"}
                ]
              },
              %FieldDefinition{
                field: :frame_size,
                label: "Fixed Frame Size (bytes)",
                type: :number,
                required: true,
                min: 1,
                visible_when: %{field: :framing_mode, equals: "fixed_size"}
              }
            ]
          },
          %SectionDefinition{
            id: "transport-reliability-section",
            number: "05B",
            title: "Reliability",
            fields: [
              %FieldDefinition{
                field: :reconnect_policy,
                label: "Reconnect Policy",
                type: :select,
                required: true,
                default: "always",
                options: [
                  {"Always reconnect", "always"},
                  {"Reconnect after disconnect", "on_disconnect"},
                  {"Do not reconnect", "none"}
                ],
                visible_when: %{field: :tcp_mode, equals: "connect"}
              },
              %FieldDefinition{
                field: :tls_enabled,
                label: "TLS",
                type: :select,
                required: true,
                default: "false",
                options: [{"Disabled", "false"}, {"Enabled", "true"}]
              }
            ]
          }
        ]
      }
    }
  end

  @impl true
  def normalize_config(config) when is_map(config) do
    with {:ok, mode} <- tcp_mode(value(config, "mode", "listen")),
         {:ok, direction_capability} <-
           direction_capability(value(config, "direction_capability", value(config, "direction"))),
         {:ok, host} <- required_text(value(config, "host"), "Host is required."),
         {:ok, port} <- port(value(config, "port")),
         {:ok, allowlist} <- listener_allowlist(config, mode),
         {:ok, framing_mode} <- framing_mode(value(config, "framing_mode", framing_value(config))),
         {:ok, frame_size} <-
           frame_size(
             value(config, "fixed_message_bytes", value(config, "frame_size")),
             framing_mode
           ),
         {:ok, reconnect_policy} <-
           reconnect_policy(value(config, "reconnect_policy", reconnect_value(config)), mode),
         {:ok, tls_enabled} <- boolean(value(config, "tls_enabled", tls_value(config))),
         {:ok, ingress_protocol_family} <-
           ingress_protocol_family(value(config, "ingress_protocol_family")),
         {:ok, ingress_metadata} <- ingress_metadata(value(config, "ingress_metadata", %{})),
         {:ok, resource_id} <- uplink_resource_id(value(config, "uplink_resource_id")) do
      {:ok,
       %{
         "adapter" => "tcp_socket",
         "mode" => mode,
         "direction_capability" => direction_capability,
         "host" => host,
         "port" => port,
         "framing" => compact(%{"mode" => framing_mode, "fixed_message_bytes" => frame_size}),
         "tls" => %{"enabled" => tls_enabled},
         "reconnect" => reconnect_configuration(mode, reconnect_policy)
       }
       |> maybe_put_uplink_resource(resource_id)
       |> maybe_put_allowlist(allowlist)
       |> maybe_put_fixed_message_bytes(frame_size)
       |> maybe_put_ingress_protocol_family(ingress_protocol_family)
       |> maybe_put_ingress_metadata(ingress_metadata)
       |> put_listener_options(config)}
    end
  end

  defp listener_allowlist(config, mode) do
    peers = value(config, "expected_peer_addresses")

    if value(config, "delivery_auth") in [:mtls, "mtls"] and peers in [nil, []],
      do: {:ok, nil},
      else: allowlist(peers, mode)
  end

  defp put_listener_options(normalized, input) do
    for key <- ["delivery_auth", "delivery_credential_ref", "listener"],
        option = value(input, key),
        not is_nil(option),
        reduce: normalized do
      config -> Map.put(config, key, option)
    end
  end

  @impl true
  def validate_config(config) when is_map(config) do
    case normalize_config(config) do
      {:ok, _normalized} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def display_summary(config) when is_map(config) do
    normalized =
      case normalize_config(config) do
        {:ok, normalized} -> normalized
        {:error, _reason} -> config
      end

    framing = Map.get(normalized, "framing", %{})

    %{
      endpoint:
        "#{Map.get(normalized, "host", "unknown")}:#{Map.get(normalized, "port", "unknown")}",
      mode: Map.get(normalized, "mode", "unknown"),
      direction_capability: Map.get(normalized, "direction_capability", "unknown"),
      framing: Map.get(framing, "mode", "raw"),
      tls_enabled?: get_in(normalized, ["tls", "enabled"]) == true
    }
  end

  @doc "Derives read-only TCP setup from a synchronized provider Delivery Profile."
  @impl true
  @spec from_delivery_profile(map()) :: {:ok, map()} | {:error, binary()}
  def from_delivery_profile(%{"direction" => "downlink"} = profile) do
    diagnostics = value(profile, "diagnostics", %{})

    with "ready" <- value(profile, "state"),
         "realtime_stream" <- value(profile, "delivery_kind"),
         "tcp" <- value(diagnostics, "protocol"),
         "provider_connects" <- value(diagnostics, "mode"),
         host when is_binary(host) and host != "" <- value(diagnostics, "host"),
         port when is_integer(port) and port > 0 and port <= 65_535 <-
           value(diagnostics, "port"),
         "ccsds_tm" <- value(diagnostics, "framing_family"),
         frame_bytes when is_integer(frame_bytes) and frame_bytes > 0 <-
           value(diagnostics, "frame_bytes") do
      normalize_config(%{
        "mode" => "listen",
        "direction_capability" => "inbound",
        "host" => host,
        "port" => port,
        "framing_mode" => "fixed_size",
        "frame_size" => frame_bytes,
        "reconnect_policy" => "on_disconnect",
        "expected_peer_addresses" => profile |> value("egress", %{}) |> value("source_addresses"),
        "delivery_auth" => value(profile, "delivery_auth"),
        "delivery_credential_ref" =>
          profile |> value("egress", %{}) |> value("delivery_credential_ref"),
        "listener" => value(diagnostics, "listener"),
        "tls_enabled" => false,
        "ingress_protocol_family" => "tm",
        "ingress_metadata" => %{"frame_size" => frame_bytes, "ocf_length" => 0}
      })
    else
      _other ->
        {:error,
         "Delivery profile is not a ready provider-connects TCP downlink with fixed-size CCSDS TM framing."}
    end
  end

  # Uplink (#44): Cadence listens; the provider connects, receives TC frames and answers with
  # 4-byte CLCWs, which reach the path's uplink gateway (linked at path resolution).
  def from_delivery_profile(%{"direction" => "uplink"} = profile) do
    diagnostics = value(profile, "diagnostics", %{})

    with "ready" <- value(profile, "state"),
         "realtime_stream" <- value(profile, "delivery_kind"),
         "tcp" <- value(diagnostics, "protocol"),
         "provider_connects" <- value(diagnostics, "mode"),
         host when is_binary(host) and host != "" <- value(diagnostics, "host"),
         port when is_integer(port) and port > 0 and port <= 65_535 <-
           value(diagnostics, "port"),
         "ccsds_tc" <- value(diagnostics, "framing_family"),
         tc_frame_bytes when is_integer(tc_frame_bytes) and tc_frame_bytes > 0 <-
           value(diagnostics, "frame_bytes") do
      normalize_config(%{
        "mode" => "listen",
        "direction_capability" => "outbound",
        "host" => host,
        "port" => port,
        "framing_mode" => "fixed_size",
        "fixed_message_bytes" => 4,
        "reconnect_policy" => "on_disconnect",
        "expected_peer_addresses" => profile |> value("egress", %{}) |> value("source_addresses"),
        "tls_enabled" => false,
        "ingress_protocol_family" => "cop1_clcw",
        "uplink_resource_id" => "uplink:#{host}:#{port}"
      })
    else
      _other ->
        {:error,
         "Delivery profile is not a ready provider-connects TCP uplink with fixed-size CCSDS TC framing."}
    end
  end

  def from_delivery_profile(_profile),
    do:
      {:error,
       "Delivery profile is not a ready provider-connects TCP downlink with fixed-size CCSDS TM framing."}

  @doc """
  Why a provider's delivery profile can't give a listening transport its source allowlist (#990,
  DECISIONS #115), as a stable code: `nil` when its `egress.source_addresses` is usable, else
  `:provider_egress_addresses_missing` (absent or empty), `:provider_egress_addresses_too_broad`
  (an entry allows every address) or `:provider_egress_addresses_invalid` (an entry isn't an
  address or range).
  """
  @spec egress_refusal(map()) :: atom() | nil
  def egress_refusal(profile) when is_map(profile) do
    peers = profile |> value("egress", %{}) |> egress_addresses()

    case PeerAddresses.classify(peers) do
      :ok ->
        nil

      :empty ->
        if value(profile, "delivery_auth") == "mtls",
          do: nil,
          else: :provider_egress_addresses_missing

      :too_broad ->
        :provider_egress_addresses_too_broad

      :invalid ->
        :provider_egress_addresses_invalid
    end
  end

  defp egress_addresses(egress) when is_map(egress), do: value(egress, "source_addresses")
  defp egress_addresses(_egress), do: nil

  @impl true
  def materialize_provider_profile(%Transport{transport_kind: :tcp_socket} = transport) do
    with {:ok, config} <- normalize_config(transport.configuration) do
      provider_config =
        config
        |> Map.put("direction", provider_direction(config["direction_capability"]))
        |> Map.delete("direction_capability")

      {:ok,
       ProviderProfile.new(%{
         mission_id: transport.mission_id,
         adapter_key: :tcp_socket,
         configuration: provider_config,
         metadata: %{
           "display_name" => transport.display_name,
           "materialized_from_transport_id" => transport.transport_id,
           "materialized_from_transport_version" => transport.version,
           "transport_origin" => Atom.to_string(transport.origin),
           "mission_provider_id" => transport.mission_provider_id,
           "mission_provider_version" => transport.mission_provider_version,
           "service_profile_ref" => transport.service_profile_ref,
           "delivery_profile_ref" => transport.delivery_profile_ref
         }
       })}
    end
  end

  defp provider_direction("inbound"), do: "downlink"
  defp provider_direction("outbound"), do: "uplink"
  defp provider_direction("bidirectional"), do: "bidirectional"

  defp value(config, key, default \\ nil) do
    atom_key = Map.fetch!(@config_atom_keys, key)
    Map.get(config, key, Map.get(config, atom_key, default))
  end

  defp framing_value(config), do: config |> value("framing", %{}) |> value("mode", "raw")
  defp reconnect_value(config), do: config |> value("reconnect", %{}) |> value("policy", "none")
  defp tls_value(config), do: config |> value("tls", %{}) |> value("enabled", false)
end
