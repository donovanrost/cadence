defmodule CadenceSimulator.CadenceRuntimeBootstrapTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.CadenceRuntimeBootstrap
  alias CadenceSimulator.Providers.DatabaseDynamics
  alias CadenceSimulator.TestSupport.FakeCadenceRuntimeBootstrapClient

  test "resolves telemetry output and tm framing from a Cadence path runtime snapshot" do
    FakeCadenceRuntimeBootstrapClient.put_response(
      {:ok,
       %{
         "path_id" => "downlink-path-alpha",
         "provider_runtimes" => [
           %{
             "provider_binding_id" => "tcp-downlink-provider",
             "adapter_key" => "tcp_socket",
             "mode" => "listen",
             "host" => "127.0.0.1",
             "port" => 4100,
             "ingress_protocol_family" => "tm",
             "fixed_message_bytes" => 1115
           }
         ],
         "transport_runtimes" => []
       }}
    )

    runtime_opts = [
      runtime_mode: :telemetry,
      definitions_path: "priv/databases/demo_spacecraft.yaml",
      provider: DatabaseDynamics,
      cadence_url: "http://127.0.0.1:4001",
      api_token: "token-alpha",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      realized_contact_id: "contact-alpha_run",
      path_id: "downlink-path-alpha"
    ]

    assert {:ok, resolved_opts} =
             CadenceRuntimeBootstrap.resolve_runtime_opts(
               runtime_opts,
               http_client: FakeCadenceRuntimeBootstrapClient
             )

    assert resolved_opts[:output] == {:tcp, "127.0.0.1", 4100}
    assert resolved_opts[:frame] == %{format: :tm, frame_size: 1115, scid: 0, vcid: 0}

    assert {CadenceRuntimeBootstrap, :refresh_runtime_opts, [_resolver_opts]} =
             resolved_opts[:runtime_resolver]

    refute Keyword.has_key?(resolved_opts, :cadence_url)
    refute Keyword.has_key?(resolved_opts, :api_token)
  end

  test "telemetry bootstrap overrides stale local output and framing" do
    FakeCadenceRuntimeBootstrapClient.put_response(
      {:ok,
       %{
         "path_id" => "downlink-path-alpha",
         "provider_runtimes" => [
           %{
             "provider_binding_id" => "tcp-downlink-provider",
             "adapter_key" => "tcp_socket",
             "mode" => "listen",
             "host" => "127.0.0.1",
             "port" => 4100,
             "ingress_protocol_family" => "tm",
             "fixed_message_bytes" => 1115
           }
         ],
         "transport_runtimes" => []
       }}
    )

    runtime_opts = [
      runtime_mode: :telemetry,
      definitions_path: "priv/databases/demo_spacecraft.yaml",
      provider: DatabaseDynamics,
      output: {:tcp, "127.0.0.1", 9999},
      frame: %{format: :tm, frame_size: 32, scid: 9, vcid: 9},
      cadence_url: "http://127.0.0.1:4001",
      api_token: "token-alpha",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      realized_contact_id: "contact-alpha_run",
      path_id: "downlink-path-alpha"
    ]

    assert {:ok, resolved_opts} =
             CadenceRuntimeBootstrap.resolve_runtime_opts(
               runtime_opts,
               http_client: FakeCadenceRuntimeBootstrapClient
             )

    assert resolved_opts[:output] == {:tcp, "127.0.0.1", 4100}
    assert resolved_opts[:frame] == %{format: :tm, frame_size: 1115, scid: 0, vcid: 0}
  end

  test "telemetry runtime resolver tuple refreshes runtime opts" do
    FakeCadenceRuntimeBootstrapClient.put_response(
      {:ok,
       %{
         "path_id" => "downlink-path-alpha",
         "provider_runtimes" => [
           %{
             "provider_binding_id" => "tcp-downlink-provider",
             "adapter_key" => "tcp_socket",
             "mode" => "listen",
             "host" => "127.0.0.1",
             "port" => 4100,
             "ingress_protocol_family" => "tm",
             "fixed_message_bytes" => 1115
           }
         ],
         "transport_runtimes" => []
       }}
    )

    runtime_opts = [
      runtime_mode: :telemetry,
      definitions_path: "priv/databases/demo_spacecraft.yaml",
      provider: DatabaseDynamics,
      cadence_url: "http://127.0.0.1:4001",
      api_token: "token-alpha",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      realized_contact_id: "contact-alpha_run",
      path_id: "downlink-path-alpha"
    ]

    assert {:ok, resolved_opts} =
             CadenceRuntimeBootstrap.resolve_runtime_opts(
               runtime_opts,
               http_client: FakeCadenceRuntimeBootstrapClient
             )

    assert {module, function, args} = resolved_opts[:runtime_resolver]
    assert {:ok, refreshed_opts} = apply(module, function, args)
    assert refreshed_opts[:output] == {:tcp, "127.0.0.1", 4100}
    assert refreshed_opts[:frame] == %{format: :tm, frame_size: 1115, scid: 0, vcid: 0}
  end

  test "resolves cop1 loopback socket and tc frame size from Cadence path runtime snapshot" do
    FakeCadenceRuntimeBootstrapClient.put_response(
      {:ok,
       %{
         "path_id" => "uplink-path-alpha",
         "provider_runtimes" => [
           %{
             "provider_binding_id" => "tcp-uplink-provider",
             "adapter_key" => "tcp_socket",
             "mode" => "listen",
             "host" => "127.0.0.1",
             "port" => 4200
           }
         ],
         "transport_runtimes" => [
           %{
             "capability_instance_id" => "uplink-gateway-alpha",
             "family_key" => "uplink_gateway",
             "state" => %{"frame_size" => 32, "segment_header_flag" => 1}
           }
         ]
       }}
    )

    runtime_opts = [
      runtime_mode: :cop1_loopback,
      cadence_url: "http://127.0.0.1:4001",
      api_token: "token-alpha",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      realized_contact_id: "contact-alpha_run",
      path_id: "uplink-path-alpha"
    ]

    assert {:ok, resolved_opts} =
             CadenceRuntimeBootstrap.resolve_runtime_opts(
               runtime_opts,
               http_client: FakeCadenceRuntimeBootstrapClient
             )

    assert resolved_opts[:host] == "127.0.0.1"
    assert resolved_opts[:port] == 4200
    assert resolved_opts[:tc_frame_size] == 32
    assert resolved_opts[:segment_header_flag] == 1

    assert {CadenceRuntimeBootstrap, :refresh_runtime_opts, [_resolver_opts]} =
             resolved_opts[:runtime_resolver]

    refute Keyword.has_key?(resolved_opts, :cadence_url)
  end

  test "cop1 loopback bootstrap overrides stale local socket settings" do
    FakeCadenceRuntimeBootstrapClient.put_response(
      {:ok,
       %{
         "path_id" => "uplink-path-alpha",
         "provider_runtimes" => [
           %{
             "provider_binding_id" => "tcp-uplink-provider",
             "adapter_key" => "tcp_socket",
             "mode" => "listen",
             "host" => "127.0.0.1",
             "port" => 4200
           }
         ],
         "transport_runtimes" => [
           %{
             "capability_instance_id" => "uplink-gateway-alpha",
             "family_key" => "uplink_gateway",
             "state" => %{"frame_size" => 32}
           }
         ]
       }}
    )

    runtime_opts = [
      runtime_mode: :cop1_loopback,
      host: "127.0.0.1",
      port: 9999,
      tc_frame_size: 8,
      cadence_url: "http://127.0.0.1:4001",
      api_token: "token-alpha",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      realized_contact_id: "contact-alpha_run",
      path_id: "uplink-path-alpha"
    ]

    assert {:ok, resolved_opts} =
             CadenceRuntimeBootstrap.resolve_runtime_opts(
               runtime_opts,
               http_client: FakeCadenceRuntimeBootstrapClient
             )

    assert resolved_opts[:host] == "127.0.0.1"
    assert resolved_opts[:port] == 4200
    assert resolved_opts[:tc_frame_size] == 32
  end

  test "requires provider selection when a path exposes more than one tcp provider runtime" do
    FakeCadenceRuntimeBootstrapClient.put_response(
      {:ok,
       %{
         "path_id" => "downlink-path-alpha",
         "provider_runtimes" => [
           %{
             "provider_binding_id" => "tcp-downlink-provider-a",
             "adapter_key" => "tcp_socket",
             "mode" => "listen",
             "host" => "127.0.0.1",
             "port" => 4100
           },
           %{
             "provider_binding_id" => "tcp-downlink-provider-b",
             "adapter_key" => "tcp_socket",
             "mode" => "listen",
             "host" => "127.0.0.1",
             "port" => 4101
           }
         ],
         "transport_runtimes" => []
       }}
    )

    runtime_opts = [
      runtime_mode: :telemetry,
      definitions_path: "priv/databases/demo_spacecraft.yaml",
      provider: DatabaseDynamics,
      cadence_url: "http://127.0.0.1:4001",
      api_token: "token-alpha",
      organization_id: "org-alpha",
      mission_id: "mission-alpha",
      realized_contact_id: "contact-alpha_run",
      path_id: "downlink-path-alpha"
    ]

    assert {:error, :provider_runtime_selection_required} =
             CadenceRuntimeBootstrap.resolve_runtime_opts(
               runtime_opts,
               http_client: FakeCadenceRuntimeBootstrapClient
             )
  end
end
