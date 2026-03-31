defmodule CadenceSimulator.SimulatorContactBootstrapTest do
  use ExUnit.Case, async: true

  alias CadenceSimulator.SimulatorContactBootstrap
  alias CadenceSimulator.TestSupport.FakeSimulatorContactBootstrapClient

  test "bootstraps scope through bootstrap-admin login and switches mission resource creation to the issued mission token" do
    definitions_path = write_definitions!("spacecraft: demo\n")

    FakeSimulatorContactBootstrapClient.put_responses([
      %{
        status: 201,
        body: %{
          "data" => %{
            "session_token" => "bootstrap-session",
            "user" => %{"user_id" => "bootstrap-admin"}
          }
        }
      },
      %{
        status: 201,
        body: %{
          "data" => %{
            "service_identity" => %{
              "service_identity_id" => "svc-bootstrap",
              "api_token" => "org-token"
            }
          }
        }
      },
      %{
        status: 201,
        body: %{
          "data" => %{
            "service_identity" => %{"service_identity_id" => "svc-simulator-mission-alpha"},
            "api_token" => "mission-token"
          }
        }
      },
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
              "telemetry_snapshot" => %{"snapshot_id" => "telemetry-snapshot-alpha"},
              "command_snapshot" => %{"snapshot_id" => "command-snapshot-alpha"}
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
      %{status: 201, body: %{"data" => %{"scheduled_contact_id" => "contact-alpha-run"}}},
      %{status: 200, body: %{"data" => %{"realized_contact_id" => "contact-alpha-run_run"}}}
    ])

    summary =
      SimulatorContactBootstrap.run(
        %{
          bootstrap_admin_email: "bootstrap@example.com",
          bootstrap_admin_password: "bootstrap-secret",
          organization_id: "org-alpha",
          organization_slug: "org-alpha",
          organization_display_name: "Org Alpha",
          mission_id: "mission-alpha",
          mission_slug: "mission-alpha",
          mission_display_name: "Mission Alpha",
          service_identity_id: "svc-bootstrap",
          service_identity_display_name: "Bootstrap Service",
          spacecraft_id: "spacecraft-001",
          spacecraft_display_name: "SC-001",
          source_endpoint_id: "source-endpoint-001",
          source_ref: "sc-001",
          source_endpoint_display_name: "SC-001 Primary Endpoint",
          definitions_path: definitions_path,
          provider_profile_id: "tcp-downlink-profile",
          transport_profile_id: "uplink-gateway-profile",
          downlink_path_template_id: "downlink-template-alpha",
          uplink_path_template_id: "uplink-template-alpha",
          downlink_path_id: "downlink-path-alpha",
          uplink_path_id: "uplink-path-alpha",
          scheduled_contact_id: "contact-alpha",
          provider_contact_ref: "provider-contact-001"
        },
        req_client: FakeSimulatorContactBootstrapClient,
        print_summary?: false
      )

    assert summary.api_token == "mission-token"

    assert get_in(summary, [:issued_service_identity, "service_identity", "service_identity_id"]) ==
             "svc-simulator-mission-alpha"

    [login_request, bootstrap_request, issue_identity_request, spacecraft_lookup, spacecraft_create | _rest] =
      FakeSimulatorContactBootstrapClient.requests()

    assert login_request.opts[:url] == "/bootstrap_admin/login"
    assert bootstrap_request.opts[:url] == "/bootstrap"
    assert request_header(bootstrap_request.request, "authorization") == "Bearer bootstrap-session"
    assert request_header(issue_identity_request.request, "authorization") == "Bearer org-token"
    assert spacecraft_lookup.method == :get
    assert request_header(spacecraft_create.request, "authorization") == "Bearer mission-token"
  end

  test "uses the provided api token without calling bootstrap admin login or bootstrap" do
    definitions_path = write_definitions!("spacecraft: demo\n")

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
              "telemetry_snapshot" => %{"snapshot_id" => "telemetry-snapshot-alpha"},
              "command_snapshot" => %{"snapshot_id" => "command-snapshot-alpha"}
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
      %{status: 201, body: %{"data" => %{"scheduled_contact_id" => "contact-alpha-run"}}},
      %{status: 200, body: %{"data" => %{"realized_contact_id" => "contact-alpha-run_run"}}}
    ])

    summary =
      SimulatorContactBootstrap.run(
        %{
          api_token: "provided-token",
          organization_id: "org-alpha",
          mission_id: "mission-alpha",
          definitions_path: definitions_path,
          source_endpoint_id: "source-endpoint-001",
          source_ref: "sc-001",
          spacecraft_id: "spacecraft-001",
          downlink_path_template_id: "downlink-template-alpha",
          uplink_path_template_id: "uplink-template-alpha",
          downlink_path_id: "downlink-path-alpha",
          uplink_path_id: "uplink-path-alpha",
          provider_profile_id: "tcp-downlink-profile",
          transport_profile_id: "uplink-gateway-profile",
          provider_contact_ref: "provider-contact-001"
        },
        req_client: FakeSimulatorContactBootstrapClient,
        print_summary?: false
      )

    assert summary.api_token == "provided-token"
    assert summary.issued_service_identity == nil

    [first_request | _rest] = FakeSimulatorContactBootstrapClient.requests()

    assert first_request.method == :get
    assert first_request.opts[:url] ==
             "/organizations/org-alpha/missions/mission-alpha/spacecraft/spacecraft-001"

    assert request_header(first_request.request, "authorization") == "Bearer provided-token"
  end

  test "uses bootstrap-admin auth on an already bootstrapped system and reuses an active realized contact" do
    definitions_path = write_definitions!("spacecraft: demo\n")

    FakeSimulatorContactBootstrapClient.put_responses([
      %{
        status: 201,
        body: %{
          "data" => %{
            "session_token" => "bootstrap-session",
            "user" => %{"user_id" => "bootstrap-admin"}
          }
        }
      },
      %{status: 409, body: %{"errors" => [%{"reason" => "bootstrap_already_completed"}]}},
      %{status: 200, body: %{"data" => %{"spacecraft_id" => "spacecraft-001"}}},
      %{status: 200, body: %{"data" => %{"source_endpoint_id" => "source-endpoint-001"}}},
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
      %{status: 200, body: %{"data" => %{"provider_profile_id" => "tcp-downlink-profile"}}},
      %{status: 200, body: %{"data" => %{"transport_profile_id" => "uplink-gateway-profile"}}},
      %{status: 200, body: %{"data" => %{"path_template_id" => "uplink-template-alpha"}}},
      %{status: 200, body: %{"data" => %{"path_template_id" => "downlink-template-alpha"}}},
      %{
        status: 200,
        body: %{
          "data" => [
            %{
              "realized_contact_id" => "contact-alpha_run",
              "scheduled_contact_id" => "contact-alpha",
              "lifecycle_state" => "active",
              "paths" => [
                %{
                  "path_id" => "downlink-path-alpha",
                  "source_endpoint_ref" => "source-endpoint-001"
                }
              ]
            }
          ]
        }
      },
      %{status: 200, body: %{"data" => %{"provider_runtimes" => []}}},
      %{status: 200, body: %{"data" => %{"scheduled_contact_id" => "contact-alpha"}}}
    ])

    summary =
      SimulatorContactBootstrap.run(
        %{
          bootstrap_admin_email: "bootstrap@example.com",
          bootstrap_admin_password: "bootstrap-secret",
          issue_mission_token: false,
          organization_id: "org-alpha",
          mission_id: "mission-alpha",
          definitions_path: definitions_path,
          source_endpoint_id: "source-endpoint-001",
          source_ref: "sc-001",
          spacecraft_id: "spacecraft-001",
          downlink_path_template_id: "downlink-template-alpha",
          uplink_path_template_id: "uplink-template-alpha",
          downlink_path_id: "downlink-path-alpha",
          uplink_path_id: "uplink-path-alpha",
          provider_profile_id: "tcp-downlink-profile",
          transport_profile_id: "uplink-gateway-profile",
          provider_contact_ref: "provider-contact-001"
        },
        req_client: FakeSimulatorContactBootstrapClient,
        print_summary?: false
      )

    assert summary.api_token == "bootstrap-session"
    assert get_in(summary, [:realized_contact, "realized_contact_id"]) == "contact-alpha_run"

    requests = FakeSimulatorContactBootstrapClient.requests()

    refute Enum.any?(requests, fn request ->
             request.method == :post &&
               request.opts[:url] == "/organizations/org-alpha/missions/mission-alpha/scheduled_contacts"
           end)

    refute Enum.any?(requests, fn request ->
             request.method == :post &&
               String.ends_with?(request.opts[:url], "/scheduled_contacts/contact-alpha/realize")
           end)
  end

  defp request_header(request, header_name) do
    request
    |> Keyword.get(:headers, [])
    |> Enum.find_value(fn
      {^header_name, value} -> value
      _other -> nil
    end)
  end

  defp write_definitions!(contents) do
    path =
      Path.join(
        System.tmp_dir!(),
        "cadence_simulator_bootstrap_#{System.unique_integer([:positive])}.yaml"
      )

    File.write!(path, contents)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    path
  end
end
