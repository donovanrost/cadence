defmodule CadenceSimulator.CLITest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.CLI
  alias CadenceSimulator.Providers.{DatabaseDynamics, ScenarioProvider}

  test "parse_args defaults to telemetry mode and builds coordinator options" do
    assert {:ok, opts} =
             CLI.parse_args([
               "--target",
               "SIM-42",
               "--definitions",
               "priv/databases/demo_spacecraft.yaml",
               "--rate",
               "25.0",
               "--tcp",
               "127.0.0.1:4100",
               "--provider",
               "database",
               "--noise-amplitude",
               "0.5",
               "--tm-frame-size",
               "1115",
               "--scid",
               "11",
               "--vcid",
               "2",
               "--fecf",
               "--parallel",
               "--tm-parallel-framing",
               "--generator-count",
               "4",
               "--metrics-sample-rate",
               "250",
               "--send-batch-timeout",
               "50",
               "--send-batch-size",
               "8192"
             ])

    assert opts[:runtime_mode] == :telemetry
    refute Keyword.has_key?(opts, :mission_id)
    assert opts[:target_id] == "SIM-42"
    assert opts[:definitions_path] == "priv/databases/demo_spacecraft.yaml"
    assert opts[:rate_hz] == 25.0
    assert opts[:output] == {:tcp, "127.0.0.1", 4100}
    assert opts[:provider] == DatabaseDynamics
    assert opts[:noise_amplitude] == 0.5
    assert opts[:parallel_mode] == :parallel
    assert opts[:tm_parallel_framing] == true
    assert opts[:generator_count] == 4
    assert opts[:metrics_sample_rate] == 250
    assert opts[:send_batch_timeout] == 50
    assert opts[:send_batch_size] == 8192

    assert opts[:frame] == %{format: :tm, frame_size: 1115, scid: 11, vcid: 2, fecf: true}
  end

  test "parse_args infers the scenario provider from --scenario" do
    assert {:ok, opts} =
             CLI.parse_args([
               "--definitions",
               "priv/databases/demo_spacecraft.yaml",
               "--scenario",
               "priv/scenarios/demo.yaml"
             ])

    assert opts[:runtime_mode] == :telemetry
    assert opts[:provider] == ScenarioProvider
    assert opts[:scenario_path] == "priv/scenarios/demo.yaml"
  end

  test "parse_args rejects missing required scenario config" do
    assert {:error, message} =
             CLI.parse_args([
               "--definitions",
               "priv/databases/demo_spacecraft.yaml",
               "--provider",
               "scenario"
             ])

    assert message =~ "--scenario is required when --provider scenario is used"
    assert message =~ "cadence_simulator [telemetry] --definitions PATH [options]"
  end

  test "parse_args builds cop1_loopback runtime options" do
    assert {:ok, opts} =
             CLI.parse_args([
               "cop1_loopback",
               "--tcp",
               "127.0.0.1:4100",
               "--tc-frame-size",
               "32",
               "--fecf",
               "--farm-initial-vr",
               "17",
               "--farm-positive-window-width",
               "200",
               "--farm-negative-window-width",
               "20",
               "--no-farm-retransmission-allowed"
             ])

    assert opts[:runtime_mode] == :cop1_loopback
    assert opts[:host] == "127.0.0.1"
    assert opts[:port] == 4100
    assert opts[:tc_frame_size] == 32
    assert opts[:fecf]
    assert opts[:farm_initial_vr] == 17
    assert opts[:farm_positive_window_width] == 200
    assert opts[:farm_negative_window_width] == 20
    refute opts[:farm_retransmission_allowed]
  end

  test "parse_args loads telemetry runtime options from yaml config" do
    config_path =
      write_config!("""
      simulator:
        runtime_mode: telemetry
        target: SIM-CONFIG
        definitions: priv/databases/demo_spacecraft.yaml
        rate: 12.5
        cadence:
          url: http://127.0.0.1:4001
          api_token: token-alpha
          organization_id: org-alpha
          mission_id: mission-alpha
          realized_contact_id: contact-alpha_run
          path_id: downlink-path-alpha
        output:
          protocol: tcp
          host: 127.0.0.1
          port: 4200
        provider: database
        frame:
          frame_size: 1115
          scid: 5
          vcid: 2
          fecf: true
        parallel: true
        tm_parallel_framing: true
        generator_count: 3
        metrics_sample_rate: 500
      """)

    assert {:ok, opts} = CLI.parse_args(["--config", config_path])

    assert opts[:runtime_mode] == :telemetry
    assert opts[:target_id] == "SIM-CONFIG"
    assert opts[:definitions_path] == "priv/databases/demo_spacecraft.yaml"
    assert opts[:rate_hz] == 12.5
    assert opts[:cadence_url] == "http://127.0.0.1:4001"
    assert opts[:api_token] == "token-alpha"
    assert opts[:organization_id] == "org-alpha"
    assert opts[:mission_id] == "mission-alpha"
    assert opts[:realized_contact_id] == "contact-alpha_run"
    assert opts[:path_id] == "downlink-path-alpha"
    assert opts[:output] == {:tcp, "127.0.0.1", 4200}
    assert opts[:provider] == DatabaseDynamics
    assert opts[:frame] == %{format: :tm, frame_size: 1115, scid: 5, vcid: 2, fecf: true}
    assert opts[:parallel_mode] == :parallel
    assert opts[:tm_parallel_framing] == true
    assert opts[:generator_count] == 3
    assert opts[:metrics_sample_rate] == 500
  end

  test "parse_args rejects removed tm worker fast path cli flag" do
    assert {:error, message} =
             CLI.parse_args([
               "--definitions",
               "priv/databases/demo_spacecraft.yaml",
               "--tm-worker-fast-path"
             ])

    assert message =~ "invalid telemetry options"
    assert message =~ "--tm-worker-fast-path"
  end

  test "parse_args rejects removed tm worker fast path config key" do
    config_path =
      write_config!("""
      simulator:
        runtime_mode: telemetry
        definitions: priv/databases/demo_spacecraft.yaml
        tm_worker_fast_path: true
      """)

    assert {:error, message} = CLI.parse_args(["--config", config_path])
    assert message =~ "tm_worker_fast_path is no longer supported"
  end

  test "parse_args loads cop1_loopback runtime options from yaml config" do
    config_path =
      write_config!("""
      mode: cop1_loopback
      segment_header_flag: 1
      fecf: true
      farm:
        initial_vr: 23
        positive_window_width: 200
        negative_window_width: 20
        retransmission_allowed: false
      cadence:
        url: http://127.0.0.1:4001
        api_token: token-alpha
        organization_id: org-alpha
        mission_id: mission-alpha
        realized_contact_id: contact-alpha_run
        path_id: uplink-path-alpha
        provider_binding_id: tcp-uplink-provider
        transport_binding_id: uplink-gateway-alpha
      clcw:
        overrides:
          lockout: true
          report_value: 3
        schedule:
          - at: 0
            overrides:
              wait: 1
              report_value: 0
          - at: 1
            overrides:
              wait: 0
              report_value: 7
      """)

    assert {:ok, opts} = CLI.parse_args(["--config", config_path])

    assert opts[:runtime_mode] == :cop1_loopback
    assert opts[:cadence_url] == "http://127.0.0.1:4001"
    assert opts[:api_token] == "token-alpha"
    assert opts[:organization_id] == "org-alpha"
    assert opts[:mission_id] == "mission-alpha"
    assert opts[:realized_contact_id] == "contact-alpha_run"
    assert opts[:path_id] == "uplink-path-alpha"
    assert opts[:provider_binding_id] == "tcp-uplink-provider"
    assert opts[:transport_binding_id] == "uplink-gateway-alpha"
    assert opts[:segment_header_flag] == 1
    assert opts[:fecf]
    assert opts[:farm_initial_vr] == 23
    assert opts[:farm_positive_window_width] == 200
    assert opts[:farm_negative_window_width] == 20
    refute opts[:farm_retransmission_allowed]
    assert opts[:clcw_overrides] == %{"lockout" => true, "report_value" => 3}

    assert opts[:clcw_schedule] == [
             %{at: 0, overrides: %{"wait" => 1, "report_value" => 0}},
             %{at: 1, overrides: %{"wait" => 0, "report_value" => 7}}
           ]
  end

  test "parse_args lets cli values override telemetry yaml config" do
    config_path =
      write_config!("""
      runtime_mode: telemetry
      definitions: priv/databases/demo_spacecraft.yaml
      rate: 5.0
      tcp: 127.0.0.1:4400
      provider: database
      """)

    assert {:ok, opts} =
             CLI.parse_args([
               "--config",
               config_path,
               "--rate",
               "25.0"
             ])

    assert opts[:runtime_mode] == :telemetry
    assert opts[:rate_hz] == 25.0
    assert opts[:output] == {:tcp, "127.0.0.1", 4400}
  end

  test "parse_args accepts loopback bootstrap flags without local tcp socket args" do
    assert {:ok, opts} =
             CLI.parse_args([
               "cop1_loopback",
               "--cadence-url",
               "http://127.0.0.1:4001",
               "--api-token",
               "token-alpha",
               "--organization-id",
               "org-alpha",
               "--mission-id",
               "mission-alpha",
               "--realized-contact-id",
               "contact-alpha_run",
               "--path-id",
               "uplink-path-alpha"
             ])

    assert opts[:runtime_mode] == :cop1_loopback
    assert opts[:cadence_url] == "http://127.0.0.1:4001"
    assert opts[:api_token] == "token-alpha"
    assert opts[:organization_id] == "org-alpha"
    assert opts[:mission_id] == "mission-alpha"
    assert opts[:realized_contact_id] == "contact-alpha_run"
    assert opts[:path_id] == "uplink-path-alpha"
    refute Keyword.has_key?(opts, :host)
    refute Keyword.has_key?(opts, :tc_frame_size)
  end

  test "parse_args builds cop1_loopback injector options" do
    assert {:ok, opts} =
             CLI.parse_args([
               "cop1_loopback",
               "--tcp",
               "127.0.0.1:4100",
               "--tc-frame-size",
               "32",
               "--clcw-overrides",
               "lockout=true,report_value=3",
               "--clcw-overrides",
               "wait=1",
               "--clcw-schedule",
               "0:wait=1,report_value=0",
               "--clcw-schedule",
               "1:wait=0,report_value=7"
             ])

    assert opts[:runtime_mode] == :cop1_loopback
    assert opts[:clcw_overrides] == %{"lockout" => true, "report_value" => 3, "wait" => 1}

    assert opts[:clcw_schedule] == [
             %{at: 0, overrides: %{"wait" => 1, "report_value" => 0}},
             %{at: 1, overrides: %{"wait" => 0, "report_value" => 7}}
           ]
  end

  test "parse_args rejects cop1_loopback without tcp target" do
    assert {:error, message} =
             CLI.parse_args([
               "cop1_loopback",
               "--tc-frame-size",
               "32"
             ])

    assert message =~ "--tcp is required"
  end

  test "parse_args rejects invalid FARM-1 window settings" do
    assert {:error, message} =
             CLI.parse_args([
               "cop1_loopback",
               "--tcp",
               "127.0.0.1:4100",
               "--tc-frame-size",
               "32",
               "--farm-positive-window-width",
               "8",
               "--farm-negative-window-width",
               "4"
             ])

    assert message =~ "invalid FARM-1 options"
    assert message =~ "unequal_retransmission_windows"
  end

  test "parse_args rejects cop1_loopback without tc frame size" do
    assert {:error, message} =
             CLI.parse_args([
               "cop1_loopback",
               "--tcp",
               "127.0.0.1:4100"
             ])

    assert message =~ "--tc-frame-size is required"
  end

  test "parse_args returns help text" do
    assert {:help, usage} = CLI.parse_args(["--help"])
    assert usage =~ "cadence_simulator --config PATH"
    assert usage =~ "cadence_simulator [telemetry] --definitions PATH [options]"
    assert usage =~ "cadence_simulator cop1_loopback --tcp HOST:PORT --tc-frame-size BYTES"
  end

  test "parse_args returns loopback help text" do
    assert {:help, usage} = CLI.parse_args(["cop1_loopback", "--help"])
    assert usage =~ "--config PATH"
    assert usage =~ "cadence_simulator cop1_loopback --tcp HOST:PORT --tc-frame-size BYTES"
  end

  test "the test environment starts Cadence only for end-to-end integration coverage" do
    assert Mix.env() == :test
    assert :cadence in Application.spec(:cadence_simulator, :applications)
  end

  test "cadence is test-only while CCSDS is a production dependency" do
    mix_source = File.read!(Path.expand("../../mix.exs", __DIR__))

    assert mix_source =~ ~s|{:cadence, path: "../cadence", env: Mix.env(), only: :test}|

    assert mix_source =~
             ~s|{:ccsds, path: "../../packages/ccsds"}|
  end

  defp write_config!(yaml_content) do
    path =
      Path.join(
        System.tmp_dir!(),
        "cadence_simulator_cli_#{System.unique_integer([:positive])}.yaml"
      )

    File.write!(path, yaml_content)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    path
  end
end
