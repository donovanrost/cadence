defmodule Cadence.Capabilities.TransportExtensions.UplinkGateway.ConfigurationTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Capabilities.TransportExtensions.UplinkGateway.Configuration

  test "normalizes defaults without changing the gateway configuration shape" do
    assert {:ok, configuration} = Configuration.normalize(%{})

    assert configuration == %{
             service_name: nil,
             transport_profile: :tc,
             frame_size: 32,
             scid: 0,
             vcid: 0,
             bypass_flag: 0,
             control_command_flag: 0,
             segment_header_flag: 0,
             fecf: false,
             initial_frame_seq: 0,
             cop1_mode: :disabled,
             cop1_timeout_ms: 5_000,
             cop1_max_retransmit: 3,
             cop1_window_size: 1,
             cop1_timeout_type: 0,
             simulated_start_delay_ms: nil,
             simulated_completion_delay_ms: nil,
             provider_binding_id: nil,
             provider_adapter_key: nil
           }

    assert :ok = Configuration.validate(configuration)
  end

  test "normalizes string keys and nested provider configuration" do
    assert {:ok, configuration} =
             Configuration.normalize(%{
               "service_name" => "gateway",
               "tc_frame_size" => 64,
               "fecf" => true,
               "cop1_mode" => "fop",
               "provider" => %{
                 "provider_binding_id" => "provider-alpha",
                 "provider_adapter_key" => "tcp_socket"
               }
             })

    assert configuration.service_name == "gateway"
    assert configuration.frame_size == 64
    assert configuration.fecf
    assert configuration.cop1_mode == :fop
    assert configuration.provider_binding_id == "provider-alpha"
    assert configuration.provider_adapter_key == :tcp_socket
    assert :ok = Configuration.validate(configuration)
  end

  test "accepts the full FOP sliding window and timeout behavior settings" do
    assert {:ok, configuration} =
             Configuration.normalize(%{
               "cop1_mode" => "fop",
               "cop1_window_size" => 255,
               "cop1_timeout_type" => 1
             })

    assert configuration.cop1_window_size == 255
    assert configuration.cop1_timeout_type == 1
    assert :ok = Configuration.validate(configuration)

    assert {:error, {:invalid_uplink_gateway_field, :cop1_window_size, 256}} =
             configuration
             |> Map.put(:cop1_window_size, 256)
             |> Configuration.validate()

    assert {:error, {:invalid_uplink_gateway_field, :cop1_timeout_type, 2}} =
             configuration
             |> Map.put(:cop1_timeout_type, 2)
             |> Configuration.validate()
  end

  test "preserves unsupported configuration errors" do
    assert {:error, {:unsupported_uplink_gateway_configuration, :invalid}} =
             Configuration.normalize(:invalid)

    assert {:ok, configuration} = Configuration.normalize(%{"transport_profile" => "invalid"})

    assert {:error, {:unsupported_uplink_gateway_transport_profile, "invalid"}} =
             Configuration.validate(configuration)
  end

  test "requires provider identifiers and adapter keys as a pair" do
    assert {:ok, configuration} =
             Configuration.normalize(%{"provider_binding_id" => "provider-alpha"})

    assert {:error, {:invalid_uplink_gateway_provider_configuration, "provider-alpha", nil}} =
             Configuration.validate(configuration)
  end
end
