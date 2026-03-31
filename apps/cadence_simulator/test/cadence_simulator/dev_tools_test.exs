defmodule CadenceSimulator.DevToolsTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.DevTools
  alias CadenceSimulator.Providers.DatabaseDynamics
  alias CadenceSimulator.TestSupport.{
    FakeCadenceRuntimeBootstrapClient,
    FakeSimulatorContactBootstrapClient
  }

  test "resolves telemetry runtime from a named profile through bootstrap and runtime lookup" do
    dir = write_dir!()
    definitions_path = write_file!(dir, "defs.yaml", "spacecraft: demo\n")

    profile_path =
      write_file!(
        dir,
        "demo_profile.yaml",
        """
        profile_name: demo_profile
        bootstrap:
          cadence_url: http://127.0.0.1:4001
          api_token: provided-token
          organization_id: org-alpha
          mission_id: mission-alpha
          spacecraft_id: spacecraft-001
          source_endpoint_id: source-endpoint-001
          source_ref: sc-001
          definitions_path: #{Path.basename(definitions_path)}
          provider_profile_id: tcp-downlink-profile
          transport_profile_id: uplink-gateway-profile
          downlink_path_template_id: downlink-template-alpha
          uplink_path_template_id: uplink-template-alpha
          downlink_path_id: downlink-path-alpha
          uplink_path_id: uplink-path-alpha
          provider_contact_ref: provider-contact-001
        simulator:
          runtime_mode: telemetry
          definitions: #{Path.basename(definitions_path)}
          provider: database
          rate: 5.0
        profiler:
          node: cadence
          mission_id: mission-alpha
        """
      )

    FakeSimulatorContactBootstrapClient.put_responses([
      %{status: 404, body: %{"errors" => [%{"reason" => "not_found"}]}},
      %{status: 201, body: %{"data" => %{"spacecraft_id" => "spacecraft-001"}}},
      %{status: 404, body: %{"errors" => [%{"reason" => "not_found"}]}},
      %{status: 201, body: %{"data" => %{"source_endpoint_id" => "source-endpoint-001"}}},
      %{status: 201, body: %{"data" => %{"artifact_id" => "artifact-mission-alpha"}}},
      %{status: 201, body: %{"data" => %{"import_run_id" => "import-run-mission-alpha"}}},
      %{
        status: 200,
        body: %{
          "data" => %{
            "status" => "completed",
            "result_document" => %{
              "telemetry_snapshot" => %{"snapshot_id" => "telemetry-snapshot-alpha"}
            }
          }
        }
      },
      %{
        status: 200,
        body: %{
          "data" => %{
            "binding_set" => %{"binding_set_id" => "binding-set-alpha", "version" => 1}
          }
        }
      },
      %{status: 201, body: %{"data" => %{"activation_id" => "activation-alpha"}}},
      %{status: 404, body: %{"errors" => [%{"reason" => "not_found"}]}},
      %{status: 201, body: %{"data" => %{"provider_profile_id" => "tcp-downlink-profile"}}},
      %{status: 404, body: %{"errors" => [%{"reason" => "not_found"}]}},
      %{status: 201, body: %{"data" => %{"transport_profile_id" => "uplink-gateway-profile"}}},
      %{status: 404, body: %{"errors" => [%{"reason" => "not_found"}]}},
      %{status: 201, body: %{"data" => %{"path_template_id" => "uplink-template-alpha"}}},
      %{status: 404, body: %{"errors" => [%{"reason" => "not_found"}]}},
      %{status: 201, body: %{"data" => %{"path_template_id" => "downlink-template-alpha"}}},
      %{status: 200, body: %{"data" => []}},
      %{status: 201, body: %{"data" => %{"scheduled_contact_id" => "contact-alpha-1"}}},
      %{status: 200, body: %{"data" => %{"realized_contact_id" => "contact-alpha-1_run"}}}
    ])

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

    assert {:ok, resolved} =
             DevTools.resolve_profile_runtime(
               profile_path,
               [],
               req_client: FakeSimulatorContactBootstrapClient,
               http_client: FakeCadenceRuntimeBootstrapClient
             )

    assert resolved.profile.name == "demo_profile"
    assert resolved.bootstrap_summary.api_token == "provided-token"
    assert resolved.runtime_opts[:runtime_mode] == :telemetry
    assert resolved.runtime_opts[:provider] == DatabaseDynamics
    assert resolved.runtime_opts[:output] == {:tcp, "127.0.0.1", 4100}
    assert resolved.runtime_opts[:frame] == %{format: :tm, frame_size: 1115, scid: 0, vcid: 0}
    assert String.ends_with?(resolved.runtime_opts[:definitions_path], "/defs.yaml")
  end

  test "returns profiler defaults for a named profile" do
    dir = write_dir!()

    profile_path =
      write_file!(
        dir,
        "profiler_defaults.yaml",
        """
        profile_name: profiler_defaults
        profiler:
          node: cadence-dev
          mission_id: mission-dev
        """
      )

    assert {:ok, %{profile: profile, node: "cadence-dev", mission_id: "mission-dev"}} =
             DevTools.profiler_defaults(profile_path)

    assert profile.name == "profiler_defaults"
  end

  defp write_dir! do
    dir = Path.join(System.tmp_dir!(), "cadence-dev-tools-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp write_file!(dir, name, content) do
    path = Path.join(dir, name)
    File.write!(path, content)
    path
  end
end
