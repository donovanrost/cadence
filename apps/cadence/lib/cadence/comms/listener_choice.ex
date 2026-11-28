defmodule Cadence.Comms.ListenerChoice do
  @moduledoc "The listener setting and its field errors for TCP transports."

  alias Cadence.Comms.PeerAddresses
  alias Cadence.Platform.ConfigFields

  @path "configuration.listener"
  @options [{"Own listener for each pass", "own"}, {"Shared, routed by SCID", "shared"}]
  @reset_reason "Only a downlink transport that listens can share one."

  def path, do: @path
  def options, do: @options
  def reset_reason, do: @reset_reason

  def value(configuration) when is_map(configuration), do: field(configuration, :listener)
  def value(_configuration), do: nil

  def shared?(configuration), do: value(configuration) in [:shared, "shared"]

  def parse(nil), do: {:ok, nil}
  def parse(value) when value in ["own", "shared"], do: {:ok, value}
  def parse(value) when value in [:own, :shared], do: {:ok, Atom.to_string(value)}
  def parse(_value), do: {:error, :invalid_listener_choice}

  def validate("shared", config) do
    with :ok <- validate_target("shared", config["mode"], config["direction_capability"]),
         :ok <- check_framing(config) do
      check_allowlist(config)
    end
  end

  def validate(_choice, _config), do: :ok

  def validate_target("shared", mode, direction) when mode != "listen" or direction != "inbound",
    do: {:error, :shared_listener_requires_downlink}

  def validate_target(_choice, _mode, _direction), do: :ok

  defp check_framing(
         %{"framing" => %{"mode" => "fixed_size", "fixed_message_bytes" => size}} = config
       )
       when is_integer(size) and size >= 2 do
    if config["ingress_protocol_family"] in [nil, "tm", "tm_transfer_frame"],
      do: :ok,
      else: {:error, :shared_listener_requires_tm_framing}
  end

  defp check_framing(_config), do: {:error, :shared_listener_requires_tm_framing}

  def check_allowlist(config) do
    if field(config, :delivery_auth) in ["mtls", :mtls] or
         PeerAddresses.classify(field(config, :expected_peer_addresses)) == :ok,
       do: :ok,
       else: {:error, :shared_listener_requires_allowlist}
  end

  def field_error(:invalid_listener_choice),
    do:
      field_error(
        :invalid_listener_choice,
        "Choose Own listener for each pass or Shared, routed by SCID."
      )

  def field_error(:shared_listener_requires_downlink),
    do: field_error(:shared_listener_requires_downlink, @reset_reason)

  def field_error(:shared_listener_requires_tm_framing),
    do:
      field_error(
        :shared_listener_requires_tm_framing,
        "A shared listener needs fixed-size TM frames."
      )

  def field_error(:shared_listener_requires_allowlist),
    do:
      field_error(
        :shared_listener_requires_allowlist,
        "A plaintext shared listener needs valid allowed source addresses."
      )

  def field_error(:shared_listener_requires_mtls),
    do:
      field_error(
        :shared_listener_requires_mtls,
        "Sharing across provider bindings needs mutual TLS."
      )

  def field_error(:shared_listener_unavailable_mtls),
    do:
      field_error(
        :shared_listener_unavailable_mtls,
        "Mutual TLS requires a provider-managed transport with an enrolled delivery credential."
      )

  def field_error(:listen_endpoint_listener_mismatch),
    do:
      field_error(
        :listen_endpoint_listener_mismatch,
        "Listeners on one endpoint must agree on Own or Shared."
      )

  def field_error(:shared_listener_bind_mismatch),
    do:
      field_error(
        :shared_listener_bind_mismatch,
        "Shared listeners on the same port must use the same bind address."
      )

  def field_error(_reason), do: nil

  defp field_error(code, message), do: Map.put(ConfigFields.error(@path, message), :code, code)

  defp field(config, key), do: Map.get(config, Atom.to_string(key), Map.get(config, key))
end
