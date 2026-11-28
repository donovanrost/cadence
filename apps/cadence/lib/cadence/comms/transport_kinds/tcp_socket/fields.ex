defmodule Cadence.Comms.TransportKinds.TCPSocket.Fields do
  @moduledoc """
  The TCP transport kind's field rules (`Cadence.Comms.TransportKinds.TCPSocket`): each parses
  one configuration value into its stored form or a sentence naming what's wrong, and the
  `maybe_put_*` helpers add optional keys to the stored document. Split from the kind so it
  stays one screen of shape; the kind imports these.
  """

  alias Cadence.Comms.PeerAddresses

  @modes ["listen", "connect"]
  @direction_capabilities ["inbound", "outbound", "bidirectional"]
  @framing_modes ["raw", "fixed_size", "line_delimited"]
  @reconnect_policies ["none", "always", "on_disconnect"]
  @ingress_protocol_families ["tm", "tm_transfer_frame", "space_packet", "cop1_clcw"]

  def tcp_mode(value) when value in @modes, do: {:ok, value}
  def tcp_mode(value) when is_atom(value), do: tcp_mode(Atom.to_string(value))
  def tcp_mode(_value), do: {:error, "TCP mode is invalid."}

  def direction_capability("downlink"), do: {:ok, "inbound"}
  def direction_capability("uplink"), do: {:ok, "outbound"}
  def direction_capability(value) when value in @direction_capabilities, do: {:ok, value}

  def direction_capability(value) when is_atom(value),
    do: direction_capability(Atom.to_string(value))

  def direction_capability(_value), do: {:error, "Direction capability is invalid."}

  def required_text(value, message) do
    case normalize_text(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  def port(value) do
    case parse_integer(value) do
      {:ok, port} when port >= 1 and port <= 65_535 -> {:ok, port}
      _other -> {:error, "Port must be an integer from 1 to 65535."}
    end
  end

  @allowlist_required "A listening transport needs its allowed source addresses: the IP " <>
                        "addresses or CIDR ranges the provider connects from."

  # A listen endpoint without an allowlist can't be created (DECISIONS #115: until mutual TLS
  # lands, the allowlist is the only check before routing). Cadence connects out in client mode,
  # so the list doesn't apply there and isn't kept.
  def allowlist(value, "listen") do
    case PeerAddresses.normalize(value) do
      {:ok, []} -> {:error, @allowlist_required}
      {:ok, entries} -> {:ok, entries}
      {:error, _reason, message} -> {:error, "Allowed source addresses: " <> message}
    end
  end

  def allowlist(_value, "connect"), do: {:ok, nil}

  def framing_mode(value) when value in @framing_modes, do: {:ok, value}
  def framing_mode(value) when is_atom(value), do: framing_mode(Atom.to_string(value))
  def framing_mode(_value), do: {:error, "Framing mode is invalid."}

  def frame_size(value, "fixed_size") do
    case parse_integer(value) do
      {:ok, frame_size} when frame_size > 0 -> {:ok, frame_size}
      _other -> {:error, "Fixed frame size must be a positive integer."}
    end
  end

  def frame_size(_value, _framing_mode), do: {:ok, nil}

  def reconnect_policy(value, "connect") do
    case normalize_text(value) || "always" do
      policy when policy in @reconnect_policies -> {:ok, policy}
      _other -> {:error, "Reconnect policy is invalid."}
    end
  end

  def reconnect_policy(_value, "listen"), do: {:ok, "on_disconnect"}

  def boolean("true"), do: {:ok, true}
  def boolean("false"), do: {:ok, false}
  def boolean(true), do: {:ok, true}
  def boolean(false), do: {:ok, false}
  def boolean(_value), do: {:error, "TLS setting is invalid."}

  def ingress_protocol_family(nil), do: {:ok, nil}

  def ingress_protocol_family(value) when value in @ingress_protocol_families,
    do: {:ok, value}

  def ingress_protocol_family(_value),
    do: {:error, "Ingress protocol family is invalid."}

  def ingress_metadata(value) when is_map(value), do: {:ok, value}
  def ingress_metadata(_value), do: {:error, "Ingress metadata is invalid."}

  def reconnect_configuration("connect", policy), do: %{"policy" => policy}
  def reconnect_configuration("listen", _policy), do: %{"policy" => "on_disconnect"}

  def uplink_resource_id(nil), do: {:ok, nil}

  def uplink_resource_id(value) when is_binary(value) and byte_size(value) in 1..255 do
    required_text(value, "Uplink resource identity must be nonempty.")
  end

  def uplink_resource_id(_),
    do: {:error, "Uplink resource identity must be a string of at most 255 bytes."}

  def maybe_put_allowlist(config, nil), do: config

  def maybe_put_allowlist(config, entries),
    do: Map.put(config, "expected_peer_addresses", entries)

  def maybe_put_uplink_resource(config, nil), do: config
  def maybe_put_uplink_resource(config, value), do: Map.put(config, "uplink_resource_id", value)

  def maybe_put_fixed_message_bytes(configuration, nil), do: configuration

  def maybe_put_fixed_message_bytes(configuration, frame_size) do
    Map.put(configuration, "fixed_message_bytes", frame_size)
  end

  def maybe_put_ingress_protocol_family(configuration, nil), do: configuration

  def maybe_put_ingress_protocol_family(configuration, protocol_family) do
    Map.put(configuration, "ingress_protocol_family", protocol_family)
  end

  def maybe_put_ingress_metadata(configuration, metadata) when metadata == %{},
    do: configuration

  def maybe_put_ingress_metadata(configuration, metadata) do
    Map.put(configuration, "ingress_metadata", metadata)
  end

  def compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  def parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  def parse_integer(value) when is_integer(value), do: {:ok, value}
  def parse_integer(_value), do: :error

  def normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def normalize_text(value) when is_atom(value), do: Atom.to_string(value)
  def normalize_text(_value), do: nil
end
