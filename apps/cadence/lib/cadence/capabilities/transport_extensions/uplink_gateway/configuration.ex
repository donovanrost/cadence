defmodule Cadence.Capabilities.TransportExtensions.UplinkGateway.Configuration do
  @moduledoc false

  @default_transport_profile :tc
  @default_frame_size 32
  @default_cop1_timeout_ms 5_000
  @default_cop1_max_retransmit 3

  @spec normalize(map()) :: {:ok, map()} | {:error, term()}
  def normalize(%{} = configuration) do
    {:ok,
     %{
       service_name: config_value(configuration, :service_name, "service_name"),
       transport_profile:
         normalize_transport_profile(
           config_value(configuration, :transport_profile, "transport_profile")
         ),
       frame_size: configured_frame_size(configuration),
       scid: config_value_or_default(configuration, :scid, "scid", 0),
       vcid: config_value_or_default(configuration, :vcid, "vcid", 0),
       bypass_flag: config_value_or_default(configuration, :bypass_flag, "bypass_flag", 0),
       control_command_flag:
         config_value_or_default(
           configuration,
           :control_command_flag,
           "control_command_flag",
           0
         ),
       segment_header_flag:
         config_value_or_default(
           configuration,
           :segment_header_flag,
           "segment_header_flag",
           0
         ),
       fecf: config_value_or_default(configuration, :fecf, "fecf", false),
       initial_frame_seq:
         config_value_or_default(configuration, :initial_frame_seq, "initial_frame_seq", 0),
       cop1_mode: normalize_cop1_mode(config_value(configuration, :cop1_mode, "cop1_mode")),
       cop1_timeout_ms:
         config_value_or_default(
           configuration,
           :cop1_timeout_ms,
           "cop1_timeout_ms",
           @default_cop1_timeout_ms
         ),
       cop1_max_retransmit:
         config_value_or_default(
           configuration,
           :cop1_max_retransmit,
           "cop1_max_retransmit",
           @default_cop1_max_retransmit
         ),
       cop1_window_size:
         config_value_or_default(configuration, :cop1_window_size, "cop1_window_size", 1),
       simulated_start_delay_ms:
         config_value(
           configuration,
           :simulated_start_delay_ms,
           "simulated_start_delay_ms"
         ),
       simulated_completion_delay_ms:
         config_value(
           configuration,
           :simulated_completion_delay_ms,
           "simulated_completion_delay_ms"
         ),
       provider_binding_id:
         provider_config_value(configuration, :provider_binding_id, "provider_binding_id"),
       provider_adapter_key:
         normalize_provider_adapter_key(
           provider_config_value(configuration, :provider_adapter_key, "provider_adapter_key")
         )
     }}
  end

  def normalize(configuration) do
    {:error, {:unsupported_uplink_gateway_configuration, configuration}}
  end

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(normalized_configuration) when is_map(normalized_configuration) do
    with :ok <- validate_transport_profile(normalized_configuration.transport_profile),
         :ok <- validate_frame_size(normalized_configuration.frame_size),
         :ok <- validate_range(normalized_configuration.scid, 0, 1023, :scid),
         :ok <- validate_range(normalized_configuration.vcid, 0, 63, :vcid),
         :ok <- validate_flag(normalized_configuration.bypass_flag, :bypass_flag),
         :ok <-
           validate_flag(
             normalized_configuration.control_command_flag,
             :control_command_flag
           ),
         :ok <-
           validate_flag(
             normalized_configuration.segment_header_flag,
             :segment_header_flag
           ),
         :ok <- validate_boolean(normalized_configuration.fecf, :fecf),
         :ok <-
           validate_range(
             normalized_configuration.initial_frame_seq,
             0,
             255,
             :initial_frame_seq
           ),
         :ok <- validate_cop1_mode(normalized_configuration.cop1_mode),
         :ok <-
           validate_positive_integer(normalized_configuration.cop1_timeout_ms, :cop1_timeout_ms),
         :ok <-
           validate_non_negative_integer(
             normalized_configuration.cop1_max_retransmit,
             :cop1_max_retransmit
           ),
         :ok <- validate_cop1_window_size(normalized_configuration.cop1_window_size),
         :ok <- validate_optional_delay(normalized_configuration.simulated_start_delay_ms),
         :ok <- validate_optional_delay(normalized_configuration.simulated_completion_delay_ms) do
      validate_provider_configuration(
        normalized_configuration.provider_binding_id,
        normalized_configuration.provider_adapter_key
      )
    end
  end

  defp configured_frame_size(configuration) do
    config_value(configuration, :frame_size, "frame_size") ||
      config_value(configuration, :tc_frame_size, "tc_frame_size") ||
      @default_frame_size
  end

  defp config_value_or_default(configuration, atom_key, string_key, default) do
    config_value(configuration, atom_key, string_key) || default
  end

  defp config_value(configuration, atom_key, string_key) do
    cond do
      Map.has_key?(configuration, atom_key) -> Map.get(configuration, atom_key)
      Map.has_key?(configuration, string_key) -> Map.get(configuration, string_key)
      true -> nil
    end
  end

  defp provider_config_value(configuration, atom_key, string_key) do
    case config_value(configuration, :provider, "provider") do
      provider when is_map(provider) ->
        config_value(provider, atom_key, string_key) ||
          config_value(configuration, atom_key, string_key)

      _other ->
        config_value(configuration, atom_key, string_key)
    end
  end

  defp normalize_transport_profile(nil), do: @default_transport_profile
  defp normalize_transport_profile(:tc), do: :tc
  defp normalize_transport_profile("tc"), do: :tc
  defp normalize_transport_profile(other), do: other

  defp normalize_cop1_mode(nil), do: :disabled
  defp normalize_cop1_mode(:disabled), do: :disabled
  defp normalize_cop1_mode("disabled"), do: :disabled
  defp normalize_cop1_mode(:fop), do: :fop
  defp normalize_cop1_mode("fop"), do: :fop
  defp normalize_cop1_mode(other), do: other

  defp normalize_provider_adapter_key(nil), do: nil
  defp normalize_provider_adapter_key(:tcp_socket), do: :tcp_socket
  defp normalize_provider_adapter_key("tcp_socket"), do: :tcp_socket
  defp normalize_provider_adapter_key(other), do: other

  defp validate_transport_profile(:tc), do: :ok

  defp validate_transport_profile(profile),
    do: {:error, {:unsupported_uplink_gateway_transport_profile, profile}}

  defp validate_cop1_mode(mode) when mode in [:disabled, :fop], do: :ok
  defp validate_cop1_mode(mode), do: {:error, {:unsupported_uplink_gateway_cop1_mode, mode}}

  defp validate_frame_size(frame_size) when is_integer(frame_size) and frame_size > 5, do: :ok

  defp validate_frame_size(frame_size),
    do: {:error, {:invalid_uplink_gateway_frame_size, frame_size}}

  defp validate_positive_integer(value, _field) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_integer(value, field),
    do: {:error, {:invalid_uplink_gateway_field, field, value}}

  defp validate_non_negative_integer(value, _field) when is_integer(value) and value >= 0, do: :ok

  defp validate_non_negative_integer(value, field),
    do: {:error, {:invalid_uplink_gateway_field, field, value}}

  defp validate_cop1_window_size(1), do: :ok

  defp validate_cop1_window_size(value),
    do: {:error, {:unsupported_uplink_gateway_cop1_window_size, value}}

  defp validate_optional_delay(nil), do: :ok
  defp validate_optional_delay(delay_ms) when is_integer(delay_ms) and delay_ms > 0, do: :ok

  defp validate_optional_delay(delay_ms),
    do: {:error, {:invalid_uplink_gateway_delay_ms, delay_ms}}

  defp validate_provider_configuration(nil, nil), do: :ok

  defp validate_provider_configuration(provider_binding_id, provider_adapter_key)
       when is_binary(provider_binding_id) and provider_binding_id != "" and
              provider_adapter_key == :tcp_socket,
       do: :ok

  defp validate_provider_configuration(provider_binding_id, provider_adapter_key) do
    {:error,
     {:invalid_uplink_gateway_provider_configuration, provider_binding_id, provider_adapter_key}}
  end

  defp validate_flag(value, _field) when value in [0, 1], do: :ok
  defp validate_flag(value, field), do: {:error, {:invalid_uplink_gateway_flag, field, value}}

  defp validate_boolean(value, _field) when is_boolean(value), do: :ok

  defp validate_boolean(value, field),
    do: {:error, {:invalid_uplink_gateway_field, field, value}}

  defp validate_range(value, min, max, _field)
       when is_integer(value) and value >= min and value <= max,
       do: :ok

  defp validate_range(value, _min, _max, field),
    do: {:error, {:invalid_uplink_gateway_field, field, value}}
end
