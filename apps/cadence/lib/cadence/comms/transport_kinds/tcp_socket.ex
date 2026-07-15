defmodule Cadence.Comms.TransportKinds.TCPSocket do
  @moduledoc """
  TCP socket transport kind.

  The configuration is durable setup for a TCP byte-moving capability, not an
  active connection. Runtime provider profile materialization is a compatibility
  bridge for existing contact/runtime code.
  """

  @behaviour Cadence.Comms.TransportKind

  alias Cadence.Comms.Transport
  alias Cadence.Contacts.ProviderProfile

  @modes ["listen", "connect"]
  @direction_capabilities ["inbound", "outbound", "bidirectional"]
  @framing_modes ["raw", "fixed_size", "line_delimited"]
  @reconnect_policies ["none", "always", "on_disconnect"]
  @config_atom_keys %{
    "direction" => :direction,
    "direction_capability" => :direction_capability,
    "delivery_kind" => :delivery_kind,
    "diagnostics" => :diagnostics,
    "enabled" => :enabled,
    "frame_bytes" => :frame_bytes,
    "fixed_message_bytes" => :fixed_message_bytes,
    "frame_size" => :frame_size,
    "framing" => :framing,
    "framing_family" => :framing_family,
    "framing_mode" => :framing_mode,
    "host" => :host,
    "mode" => :mode,
    "policy" => :policy,
    "port" => :port,
    "protocol" => :protocol,
    "reconnect" => :reconnect,
    "reconnect_policy" => :reconnect_policy,
    "state" => :state,
    "tls" => :tls,
    "tls_enabled" => :tls_enabled
  }

  @impl true
  def form_metadata do
    %{
      form_value: "tcp_socket",
      label: "TCP socket",
      configurable_sections: [:endpoint, :framing, :reliability],
      modes: [{"TCP server (listen)", "listen"}, {"TCP client (connect)", "connect"}],
      directions: [
        {"Inbound", "inbound"},
        {"Outbound", "outbound"},
        {"Bidirectional", "bidirectional"}
      ],
      framing_modes: [
        {"Raw bytes", "raw"},
        {"Fixed-size frames", "fixed_size"},
        {"Line-delimited", "line_delimited"}
      ],
      reconnect_policies: [
        {"Always reconnect", "always"},
        {"Reconnect after disconnect", "on_disconnect"},
        {"Do not reconnect", "none"}
      ],
      tls_options: [{"Disabled", "false"}, {"Enabled", "true"}]
    }
  end

  @impl true
  def normalize_config(config) when is_map(config) do
    with {:ok, mode} <- tcp_mode(value(config, "mode", "listen")),
         {:ok, direction_capability} <-
           direction_capability(value(config, "direction_capability", value(config, "direction"))),
         {:ok, host} <- required_text(value(config, "host"), "Host is required."),
         {:ok, port} <- port(value(config, "port")),
         {:ok, framing_mode} <- framing_mode(value(config, "framing_mode", framing_value(config))),
         {:ok, frame_size} <-
           frame_size(
             value(config, "fixed_message_bytes", value(config, "frame_size")),
             framing_mode
           ),
         {:ok, reconnect_policy} <-
           reconnect_policy(value(config, "reconnect_policy", reconnect_value(config)), mode),
         {:ok, tls_enabled} <- boolean(value(config, "tls_enabled", tls_value(config))) do
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
       |> maybe_put_fixed_message_bytes(frame_size)}
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
  @spec from_delivery_profile(map()) :: {:ok, map()} | {:error, binary()}
  def from_delivery_profile(profile) when is_map(profile) do
    diagnostics = value(profile, "diagnostics", %{})

    with "ready" <- value(profile, "state"),
         "downlink" <- value(profile, "direction"),
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
        "tls_enabled" => false
      })
    else
      _other ->
        {:error,
         "Delivery profile is not a ready provider-connects TCP downlink with fixed-size CCSDS TM framing."}
    end
  end

  def from_delivery_profile(_profile),
    do:
      {:error,
       "Delivery profile is not a ready provider-connects TCP downlink with fixed-size CCSDS TM framing."}

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

  defp tcp_mode(value) when value in @modes, do: {:ok, value}
  defp tcp_mode(value) when is_atom(value), do: tcp_mode(Atom.to_string(value))
  defp tcp_mode(_value), do: {:error, "TCP mode is invalid."}

  defp direction_capability("downlink"), do: {:ok, "inbound"}
  defp direction_capability("uplink"), do: {:ok, "outbound"}
  defp direction_capability(value) when value in @direction_capabilities, do: {:ok, value}

  defp direction_capability(value) when is_atom(value),
    do: direction_capability(Atom.to_string(value))

  defp direction_capability(_value), do: {:error, "Direction capability is invalid."}

  defp required_text(value, message) do
    case normalize_text(value) do
      nil -> {:error, message}
      text -> {:ok, text}
    end
  end

  defp port(value) do
    case parse_integer(value) do
      {:ok, port} when port >= 1 and port <= 65_535 -> {:ok, port}
      _other -> {:error, "Port must be an integer from 1 to 65535."}
    end
  end

  defp framing_mode(value) when value in @framing_modes, do: {:ok, value}
  defp framing_mode(value) when is_atom(value), do: framing_mode(Atom.to_string(value))
  defp framing_mode(_value), do: {:error, "Framing mode is invalid."}

  defp frame_size(value, "fixed_size") do
    case parse_integer(value) do
      {:ok, frame_size} when frame_size > 0 -> {:ok, frame_size}
      _other -> {:error, "Fixed frame size must be a positive integer."}
    end
  end

  defp frame_size(_value, _framing_mode), do: {:ok, nil}

  defp reconnect_policy(value, "connect") do
    case normalize_text(value) || "always" do
      policy when policy in @reconnect_policies -> {:ok, policy}
      _other -> {:error, "Reconnect policy is invalid."}
    end
  end

  defp reconnect_policy(_value, "listen"), do: {:ok, "on_disconnect"}

  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(true), do: {:ok, true}
  defp boolean(false), do: {:ok, false}
  defp boolean(_value), do: {:error, "TLS setting is invalid."}

  defp reconnect_configuration("connect", policy), do: %{"policy" => policy}
  defp reconnect_configuration("listen", _policy), do: %{"policy" => "on_disconnect"}

  defp maybe_put_fixed_message_bytes(configuration, nil), do: configuration

  defp maybe_put_fixed_message_bytes(configuration, frame_size) do
    Map.put(configuration, "fixed_message_bytes", frame_size)
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _other -> :error
    end
  end

  defp parse_integer(value) when is_integer(value), do: {:ok, value}
  defp parse_integer(_value), do: :error

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_text(_value), do: nil
end
