defmodule CadenceWeb.ControlPlaneApiTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  import CadenceWeb.ControlPlaneApiFixtures

  @bootstrap_admin_email "bootstrap-admin@example.com"
  @bootstrap_admin_password "bootstrap-password-123"

  setup do
    previous_importers = Application.get_env(:cadence, :catalog_importers, [])
    previous_bootstrap_admin = Application.get_env(:cadence, :bootstrap_admin, [])

    Application.put_env(:cadence, :catalog_importers, [
      CadenceWeb.TestSupport.FakeTelemetryCatalogImporter
    ])

    Application.put_env(:cadence, :bootstrap_admin,
      enabled: true,
      user_id: "user_bootstrap_admin",
      email: @bootstrap_admin_email,
      display_name: "Bootstrap Admin",
      password: @bootstrap_admin_password,
      session_ttl_seconds: 3600
    )

    reset_bootstrap_state!()
    assert {:ok, _user} = Cadence.Auth.ensure_bootstrap_admin()

    on_exit(fn ->
      Application.put_env(:cadence, :catalog_importers, previous_importers)
      Application.put_env(:cadence, :bootstrap_admin, previous_bootstrap_admin)
    end)

    :ok
  end

  defp persist_link_assignment_prerequisites(conn, api_token, organization_id, mission_id) do
    spacecraft_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft", %{
        "spacecraft" => %{
          "spacecraft_id" => "spacecraft-link-api-001",
          "display_name" => "SC Link API 001"
        }
      })

    assert %{"data" => %{"spacecraft_id" => "spacecraft-link-api-001"}} =
             json_response(spacecraft_conn, 201)

    second_spacecraft_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft", %{
        "spacecraft" => %{
          "spacecraft_id" => "spacecraft-link-api-002",
          "display_name" => "SC Link API 002",
          "scid" => 202
        }
      })

    assert %{"data" => %{"spacecraft_id" => "spacecraft-link-api-002", "scid" => 202}} =
             json_response(second_spacecraft_conn, 201)

    source_endpoint_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft/spacecraft-link-api-001/source_endpoints",
        %{
          "source_endpoint" => %{
            "source_endpoint_id" => "source-endpoint-link-api-001",
            "source_ref" => "sc-link-api-001",
            "display_name" => "SC Link API Endpoint"
          }
        }
      )

    assert %{"data" => %{"source_endpoint_id" => "source-endpoint-link-api-001"}} =
             json_response(source_endpoint_conn, 201)

    provider_profile_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles", %{
        "provider_profile" => %{
          "provider_profile_id" => "tcp-link-api-profile",
          "adapter_key" => "tcp_socket",
          "configuration" => %{
            "mode" => "listen",
            "port" => 0,
            "ingress_protocol_family" => "tm",
            "frame_size" => 1115
          }
        }
      })

    assert %{"data" => %{"provider_profile_id" => "tcp-link-api-profile", "version" => 1}} =
             json_response(provider_profile_conn, 201)

    path_template_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/path_templates", %{
        "path_template" => %{
          "path_template_id" => "downlink-link-api-template",
          "path_id" => "downlink-link-api-path",
          "direction" => "downlink",
          "selection_role" => "selected",
          "source_endpoint_ref" => "source-endpoint-link-api-001",
          "provider_profile_ids" => ["tcp-link-api-profile"]
        }
      })

    assert %{
             "data" => %{
               "path_template_id" => "downlink-link-api-template",
               "version" => 1,
               "source_endpoint_ref" => nil
             }
           } = json_response(path_template_conn, 201)

    path_template_patch_conn =
      conn
      |> authorize(api_token)
      |> patch(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/path_templates/downlink-link-api-template",
        %{
          "path_template" => %{
            "source_endpoint_ref" => "source-endpoint-link-api-001",
            "metadata" => %{"operator_label" => "ignored direct assignment"}
          }
        }
      )

    assert %{
             "data" => %{
               "path_template_id" => "downlink-link-api-template",
               "version" => 2,
               "source_endpoint_ref" => nil
             }
           } = json_response(path_template_patch_conn, 200)
  end

  defp assert_contact_runtime_lifecycle(conn, api_token, organization_id, mission_id) do
    starts_at = DateTime.from_unix!(1_700_080_000, :second)
    ends_at = DateTime.add(starts_at, 600, :second)

    scheduled_contact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts",
        %{
          "scheduled_contact" => %{
            "scheduled_contact_id" => "contact-alpha",
            "contact_intents" => ["command_window", "telemetry_downlink"],
            "path_template_ids" => ["uplink-template-alpha", "downlink-template-alpha"],
            "starts_at" => DateTime.to_iso8601(starts_at),
            "ends_at" => DateTime.to_iso8601(ends_at),
            "provider_contact_ref" => "provider-contact-001"
          }
        }
      )

    assert %{
             "data" => %{
               "scheduled_contact_id" => "contact-alpha",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "lifecycle_state" => "scheduled",
               "contact_intents" => ["command_window", "telemetry_downlink"],
               "path_template_ids" => ["uplink-template-alpha", "downlink-template-alpha"],
               "paths" => []
             }
           } = json_response(scheduled_contact_conn, 201)

    scheduled_contacts_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts")

    assert %{
             "data" => [
               %{
                 "scheduled_contact_id" => "contact-alpha",
                 "organization_id" => ^organization_id,
                 "lifecycle_state" => "scheduled"
               }
             ]
           } = json_response(scheduled_contacts_conn, 200)

    realized_contact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts/contact-alpha/realize",
        %{
          "realization" => %{
            "clock_mode" => "replay",
            "initial_time" => DateTime.to_iso8601(starts_at),
            "transition_time" => DateTime.to_iso8601(starts_at)
          }
        }
      )

    assert %{
             "data" => %{
               "realized_contact_id" => "contact-alpha_run",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "lifecycle_state" => "active",
               "contact_intents" => ["command_window", "telemetry_downlink"],
               "clock_mode" => "replay"
             }
           } = json_response(realized_contact_conn, 200)

    realized_contact_runtime_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/realized_contacts/contact-alpha_run/runtime"
      )

    assert %{
             "data" => %{
               "realized_contact_id" => "contact-alpha_run",
               "contact_intents" => ["command_window", "telemetry_downlink"],
               "path_count" => 2,
               "paths" => [
                 %{"path_id" => "uplink-path-alpha"},
                 %{"path_id" => "downlink-path-alpha"}
               ]
             }
           } = json_response(realized_contact_runtime_conn, 200)

    path_runtime_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/realized_contacts/contact-alpha_run/paths/downlink-path-alpha/runtime"
      )

    assert %{
             "data" => %{
               "path_id" => "downlink-path-alpha",
               "provider_runtime_count" => 1,
               "provider_runtimes" => [
                 %{
                   "provider_binding_id" => "tcp-downlink-profile",
                   "adapter_key" => "tcp_socket",
                   "mode" => "listen",
                   "ingress_protocol_family" => "tm",
                   "fixed_message_bytes" => 1115,
                   "port" => runtime_port
                 }
               ]
             }
           } = json_response(path_runtime_conn, 200)

    assert is_integer(runtime_port)
    assert runtime_port > 0

    realized_contacts_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/realized_contacts")

    assert %{
             "data" => [
               %{
                 "realized_contact_id" => "contact-alpha_run",
                 "organization_id" => ^organization_id,
                 "lifecycle_state" => "active"
               }
             ]
           } = json_response(realized_contacts_conn, 200)

    ended_contact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/realized_contacts/contact-alpha_run/end_early",
        %{
          "termination" => %{
            "reason" => "operator stop"
          }
        }
      )

    assert %{
             "data" => %{
               "realized_contact_id" => "contact-alpha_run",
               "organization_id" => ^organization_id,
               "lifecycle_state" => "stopped",
               "metadata" => %{"reason" => "operator stop"}
             }
           } = json_response(ended_contact_conn, 200)

    scheduled_contact_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts/contact-alpha"
      )

    assert %{
             "data" => %{
               "scheduled_contact_id" => "contact-alpha",
               "organization_id" => ^organization_id,
               "lifecycle_state" => "canceled",
               "realized_contact_id" => "contact-alpha_run",
               "metadata" => %{"reason" => "operator stop"}
             }
           } = json_response(scheduled_contact_show_conn, 200)

    contact_actions_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/contact_actions")

    assert %{
             "data" => [
               %{
                 "action_kind" => "realized_contact_ended_early",
                 "organization_id" => ^organization_id,
                 "realized_contact_id" => "contact-alpha_run",
                 "reason" => "operator stop"
               }
             ]
           } = json_response(contact_actions_conn, 200)
  end

  defp assert_binding_set_activation(conn, api_token, organization_id, mission_id) do
    binding_set_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/binding_sets", %{
        "binding_set" => %{
          "binding_set_id" => "ops",
          "version" => 1,
          "capability_instances" => [
            %{
              "capability_instance_id" => "telemetry-default",
              "family_key" => "definition_bound_telemetry",
              "target_scope" => "mission",
              "capability_config" => %{
                "config_type" => "governed_packet_definition",
                "document" => %{
                  "mission_id" => mission_id,
                  "packet_definition_id" => "packet-def-hk",
                  "version" => 1
                }
              }
            }
          ],
          "rules" => [
            %{
              "binding_rule_id" => "tm-apid-42",
              "capability_instance_id" => "telemetry-default",
              "selector" => %{
                "scope" => %{"target_scope" => "mission"},
                "match" => %{"packet_kind" => "space_packet", "apid" => 42}
              }
            }
          ]
        }
      })

    assert %{
             "data" => %{
               "binding_set_id" => "ops",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id
             }
           } = json_response(binding_set_conn, 201)

    activation_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/activations", %{
        "activation" => %{
          "binding_set_id" => "ops",
          "version" => 1,
          "metadata" => %{"reason" => "bootstrap"}
        }
      })

    assert %{
             "data" => %{
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "binding_set_id" => "ops",
               "binding_set_version" => 1
             }
           } = json_response(activation_conn, 201)

    active_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/activations/active")

    assert %{
             "data" => %{
               "activation" => %{
                 "organization_id" => ^organization_id,
                 "binding_set_id" => "ops",
                 "binding_set_version" => 1
               },
               "binding_set" => %{
                 "organization_id" => ^organization_id,
                 "binding_set_id" => "ops",
                 "version" => 1
               }
             }
           } = json_response(active_conn, 200)
  end

  test "bootstrap admin logs in and can bootstrap the first organization", %{conn: conn} do
    bootstrap_admin_token = bootstrap_admin_login(conn)

    current_scope_conn =
      conn
      |> authorize(bootstrap_admin_token)
      |> get("/api/current_scope")

    assert %{
             "data" => %{
               "actor_kind" => "user",
               "organization" => nil,
               "mission" => nil,
               "user" => %{
                 "user_id" => "user_bootstrap_admin",
                 "email" => @bootstrap_admin_email
               },
               "service_identity" => nil,
               "capabilities" => ["platform_admin"]
             }
           } = json_response(current_scope_conn, 200)

    bootstrap_conn =
      conn
      |> authorize(bootstrap_admin_token)
      |> post("/api/bootstrap", %{
        "bootstrap" => %{
          "organization" => %{
            "organization_id" => "org-alpha",
            "slug" => "org-alpha",
            "display_name" => "Org Alpha"
          },
          "mission" => %{
            "mission_id" => "mission-alpha",
            "slug" => "mission-alpha",
            "display_name" => "Mission Alpha"
          },
          "service_identity" => %{
            "service_identity_id" => "svc-bootstrap",
            "display_name" => "Bootstrap Service"
          }
        }
      })

    assert %{
             "data" => %{
               "organization" => %{
                 "organization_id" => "org-alpha",
                 "slug" => "org-alpha"
               },
               "mission" => %{
                 "mission_id" => "mission-alpha",
                 "organization_id" => "org-alpha"
               },
               "service_identity" => %{
                 "service_identity" => %{
                   "service_identity_id" => "svc-bootstrap",
                   "organization_id" => "org-alpha",
                   "capabilities" => ["organization_admin"]
                 },
                 "api_token" => api_token
               }
             }
           } = json_response(bootstrap_conn, 201)

    org_scope_conn =
      conn
      |> authorize(api_token)
      |> get("/api/current_scope")

    assert %{
             "data" => %{
               "actor_kind" => "service",
               "organization" => %{"organization_id" => "org-alpha"},
               "mission" => nil,
               "service_identity" => %{"service_identity_id" => "svc-bootstrap"},
               "capabilities" => ["organization_admin"]
             }
           } = json_response(org_scope_conn, 200)
  end

  test "bootstrap endpoint rejects unauthenticated callers", %{conn: conn} do
    bootstrap_conn =
      post(conn, "/api/bootstrap", %{
        "bootstrap" => %{
          "organization" => %{
            "organization_id" => "org-alpha",
            "slug" => "org-alpha",
            "display_name" => "Org Alpha"
          },
          "service_identity" => %{
            "service_identity_id" => "svc-bootstrap",
            "display_name" => "Bootstrap Service"
          }
        }
      })

    assert %{"errors" => [%{"reason" => "unauthenticated"}]} = json_response(bootstrap_conn, 401)
  end

  test "org-scoped control-plane token can manage missions and mission resources", %{conn: conn} do
    %{conn: conn, api_token: api_token, organization_id: organization_id} = bootstrap(conn)

    mission_create_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions", %{
        "mission" => %{
          "mission_id" => "mission-bravo",
          "slug" => "mission-bravo",
          "display_name" => "Mission Bravo"
        }
      })

    assert %{
             "data" => %{
               "mission_id" => "mission-bravo",
               "organization_id" => ^organization_id,
               "slug" => "mission-bravo"
             }
           } = json_response(mission_create_conn, 201)

    mission_id = "mission-bravo"

    spacecraft_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft", %{
        "spacecraft" => %{
          "spacecraft_id" => "spacecraft-001",
          "display_name" => "SC-001"
        }
      })

    assert %{
             "data" => %{
               "spacecraft_id" => "spacecraft-001",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id
             }
           } = json_response(spacecraft_conn, 201)

    packet_definition_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/packet_definitions",
        %{
          "packet_definition" => %{
            "packet_definition_id" => "packet-def-hk",
            "packet_name" => "HK_PACKET",
            "apid" => 42,
            "fields" => [
              %{
                "field_id" => "field-temp",
                "name" => "temp_c",
                "offset_bits" => 0,
                "size_bits" => 16,
                "data_type" => "uint"
              }
            ]
          }
        }
      )

    assert %{
             "data" => %{
               "packet_definition_id" => "packet-def-hk",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id
             }
           } = json_response(packet_definition_conn, 201)

    source_endpoint_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft/spacecraft-001/source_endpoints",
        %{
          "source_endpoint" => %{
            "source_endpoint_id" => "source-endpoint-001",
            "source_ref" => "sc-001",
            "scid" => 23,
            "display_name" => "SC-001 Primary Endpoint"
          }
        }
      )

    assert %{
             "data" => %{
               "source_endpoint_id" => "source-endpoint-001",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "spacecraft_id" => "spacecraft-001"
             }
           } = json_response(source_endpoint_conn, 201)

    spacecraft_source_endpoints_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft/spacecraft-001/source_endpoints"
      )

    assert %{
             "data" => [
               %{
                 "source_endpoint_id" => "source-endpoint-001",
                 "spacecraft_id" => "spacecraft-001"
               }
             ]
           } = json_response(spacecraft_source_endpoints_conn, 200)

    source_endpoint_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/source_endpoints/source-endpoint-001"
      )

    assert %{
             "data" => %{
               "source_endpoint_id" => "source-endpoint-001",
               "display_name" => "SC-001 Primary Endpoint",
               "spacecraft_id" => "spacecraft-001"
             }
           } = json_response(source_endpoint_show_conn, 200)

    provider_profile_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles", %{
        "provider_profile" => %{
          "provider_profile_id" => "tcp-downlink-profile",
          "adapter_key" => "tcp_socket",
          "configuration" => %{
            "mode" => "listen",
            "port" => 0,
            "ingress_protocol_family" => "tm",
            "frame_size" => 1115,
            "ingress_metadata" => %{
              "frame_size" => 1115,
              "ocf_length" => 0
            }
          }
        }
      })

    assert %{
             "data" => %{
               "provider_profile_id" => "tcp-downlink-profile",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "adapter_key" => "tcp_socket"
             }
           } = json_response(provider_profile_conn, 201)

    transport_profile_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/transport_profiles",
        %{
          "transport_profile" => %{
            "transport_profile_id" => "uplink-gateway-profile",
            "family_key" => "uplink_gateway",
            "target_scope" => "path",
            "configuration" => %{"transport_profile" => "tc"}
          }
        }
      )

    assert %{
             "data" => %{
               "transport_profile_id" => "uplink-gateway-profile",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "family_key" => "uplink_gateway"
             }
           } = json_response(transport_profile_conn, 201)

    path_template_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/path_templates", %{
        "path_template" => %{
          "path_template_id" => "downlink-template-alpha",
          "path_id" => "downlink-path-alpha",
          "direction" => "downlink",
          "selection_role" => "selected",
          "source_endpoint_ref" => "source-endpoint-001",
          "provider_profile_ids" => ["tcp-downlink-profile"]
        }
      })

    assert %{
             "data" => %{
               "path_template_id" => "downlink-template-alpha",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "provider_profile_ids" => ["tcp-downlink-profile"]
             }
           } = json_response(path_template_conn, 201)

    uplink_path_template_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/path_templates", %{
        "path_template" => %{
          "path_template_id" => "uplink-template-alpha",
          "path_id" => "uplink-path-alpha",
          "direction" => "uplink",
          "selection_role" => "selected",
          "source_endpoint_ref" => "source-endpoint-001",
          "transport_profile_ids" => ["uplink-gateway-profile"]
        }
      })

    assert %{
             "data" => %{
               "path_template_id" => "uplink-template-alpha",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "transport_profile_ids" => ["uplink-gateway-profile"]
             }
           } = json_response(uplink_path_template_conn, 201)

    assert_contact_runtime_lifecycle(conn, api_token, organization_id, mission_id)

    assert_binding_set_activation(conn, api_token, organization_id, mission_id)
  end

  test "contact runtime config APIs expose versions and pin scheduled contact refs", %{
    conn: conn
  } do
    %{conn: conn, api_token: api_token, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    provider_profile_v1_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles", %{
        "provider_profile" => %{
          "provider_profile_id" => "tcp-downlink-versioned",
          "adapter_key" => "tcp_socket",
          "configuration" => %{
            "mode" => "listen",
            "port" => 0,
            "ingress_protocol_family" => "tm",
            "frame_size" => 1115
          }
        }
      })

    assert %{
             "data" => %{
               "provider_profile_id" => "tcp-downlink-versioned",
               "version" => 1,
               "lifecycle_state" => "active"
             }
           } = json_response(provider_profile_v1_conn, 201)

    provider_profile_v2_conn =
      conn
      |> authorize(api_token)
      |> patch(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles/tcp-downlink-versioned",
        %{
          "provider_profile" => %{
            "configuration" => %{
              "mode" => "listen",
              "port" => 4100,
              "ingress_protocol_family" => "tm",
              "frame_size" => 512
            }
          }
        }
      )

    assert %{
             "data" => %{
               "provider_profile_id" => "tcp-downlink-versioned",
               "version" => 2,
               "configuration" => %{"port" => 4100}
             }
           } = json_response(provider_profile_v2_conn, 200)

    provider_profile_versions_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles/tcp-downlink-versioned/versions"
      )

    assert %{
             "data" => [
               %{"provider_profile_id" => "tcp-downlink-versioned", "version" => 2},
               %{"provider_profile_id" => "tcp-downlink-versioned", "version" => 1}
             ]
           } = json_response(provider_profile_versions_conn, 200)

    path_template_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/path_templates", %{
        "path_template" => %{
          "path_template_id" => "downlink-template-versioned",
          "path_id" => "downlink-path-versioned",
          "direction" => "downlink",
          "selection_role" => "selected",
          "source_endpoint_ref" => "source-endpoint-001",
          "provider_profile_ids" => ["tcp-downlink-versioned"]
        }
      })

    assert %{
             "data" => %{
               "path_template_id" => "downlink-template-versioned",
               "version" => 1,
               "provider_profile_refs" => [
                 %{"provider_profile_id" => "tcp-downlink-versioned", "version" => 2}
               ]
             }
           } = json_response(path_template_conn, 201)

    scheduled_contact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts",
        %{
          "scheduled_contact" => %{
            "scheduled_contact_id" => "contact-versioned",
            "contact_intents" => ["telemetry_downlink"],
            "path_template_ids" => ["downlink-template-versioned"],
            "starts_at" => "2026-03-30T18:00:00Z",
            "ends_at" => "2026-03-30T18:10:00Z"
          }
        }
      )

    assert %{
             "data" => %{
               "scheduled_contact_id" => "contact-versioned",
               "contact_intents" => ["telemetry_downlink"],
               "path_template_refs" => [
                 %{"path_template_id" => "downlink-template-versioned", "version" => 1}
               ]
             }
           } = json_response(scheduled_contact_conn, 201)

    path_template_v2_conn =
      conn
      |> authorize(api_token)
      |> patch(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/path_templates/downlink-template-versioned",
        %{
          "path_template" => %{
            "metadata" => %{"operator_label" => "patched"}
          }
        }
      )

    assert %{
             "data" => %{
               "path_template_id" => "downlink-template-versioned",
               "version" => 2
             }
           } = json_response(path_template_v2_conn, 200)

    provider_profile_deleted_conn =
      conn
      |> authorize(api_token)
      |> delete(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles/tcp-downlink-versioned"
      )

    assert %{
             "data" => %{
               "provider_profile_id" => "tcp-downlink-versioned",
               "version" => 3,
               "lifecycle_state" => "deleted"
             }
           } = json_response(provider_profile_deleted_conn, 200)

    latest_provider_profile_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles/tcp-downlink-versioned"
      )

    assert %{"errors" => [%{"reason" => "contact_provider_profile_not_found"}]} =
             json_response(latest_provider_profile_conn, 404)

    provider_profile_v1_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/provider_profiles/tcp-downlink-versioned/versions/1"
      )

    assert %{
             "data" => %{
               "provider_profile_id" => "tcp-downlink-versioned",
               "version" => 1,
               "lifecycle_state" => "active"
             }
           } = json_response(provider_profile_v1_show_conn, 200)
  end

  test "mission-scoped API manages explicit link assignments", %{conn: conn} do
    %{conn: conn, api_token: api_token, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    persist_link_assignment_prerequisites(conn, api_token, organization_id, mission_id)

    link_assignment_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/link_assignments", %{
        "link_assignment" => %{
          "link_assignment_id" => "link-assignment-api-001",
          "spacecraft_id" => "spacecraft-link-api-001",
          "source_endpoint_ref" => "source-endpoint-link-api-001",
          "path_template_id" => "downlink-link-api-template",
          "path_template_version" => 2,
          "direction" => "downlink",
          "selection_role" => "selected",
          "provider_path_ref" => "provider-path-link-api-001",
          "provider_profile_refs" => [
            %{"provider_profile_id" => "tcp-link-api-profile", "version" => 1}
          ],
          "metadata" => %{"display_name" => "SC Link API downlink"}
        }
      })

    assert %{
             "data" => %{
               "link_assignment_id" => "link-assignment-api-001",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "lifecycle_state" => "active",
               "spacecraft_id" => "spacecraft-link-api-001",
               "source_endpoint_ref" => "source-endpoint-link-api-001",
               "path_template_id" => "downlink-link-api-template",
               "path_template_version" => 2,
               "direction" => "downlink",
               "selection_role" => "selected",
               "provider_path_ref" => "provider-path-link-api-001",
               "provider_profile_refs" => [
                 %{"provider_profile_id" => "tcp-link-api-profile", "version" => 1}
               ]
             }
           } = json_response(link_assignment_conn, 201)

    invalid_link_assignment_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/link_assignments", %{
        "link_assignment" => %{
          "link_assignment_id" => "link-assignment-api-invalid",
          "spacecraft_id" => "spacecraft-link-api-002",
          "source_endpoint_ref" => "source-endpoint-link-api-001",
          "path_template_id" => "downlink-link-api-template",
          "path_template_version" => 2,
          "direction" => "downlink",
          "selection_role" => "selected",
          "provider_profile_refs" => [
            %{"provider_profile_id" => "tcp-link-api-profile", "version" => 1}
          ]
        }
      })

    assert %{"errors" => [%{"reason" => "link_assignment_source_endpoint_mismatch"}]} =
             json_response(invalid_link_assignment_conn, 422)

    application_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/path_templates/downlink-link-api-template/link_assignments",
        %{
          "link_template_application" => %{
            "target_mode" => "selected",
            "spacecraft_ids" => ["spacecraft-link-api-002"],
            "path_template_version" => 2,
            "provider_path_ref_pattern" => "{spacecraft_id}-{direction}",
            "display_name_pattern" => "{spacecraft_name} {direction}"
          }
        }
      )

    assert %{
             "data" => %{
               "applied_count" => 1,
               "skipped_count" => 0,
               "failed_count" => 0,
               "rows" => [
                 %{
                   "spacecraft" => %{"spacecraft_id" => "spacecraft-link-api-002"},
                   "kind" => "applied",
                   "status" => "ready"
                 }
               ]
             }
           } = json_response(application_conn, 201)

    matching_application_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/path_templates/downlink-link-api-template/link_assignments",
        %{
          "link_template_application" => %{
            "target_mode" => "matching",
            "spacecraft_query" => "SC Link API",
            "path_template_version" => 2
          }
        }
      )

    assert %{
             "data" => %{
               "applied_count" => 0,
               "skipped_count" => 2,
               "failed_count" => 0
             }
           } = json_response(matching_application_conn, 201)

    link_assignments_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/link_assignments?spacecraft_id=spacecraft-link-api-001"
      )

    assert %{
             "data" => [
               %{
                 "link_assignment_id" => "link-assignment-api-001",
                 "spacecraft_id" => "spacecraft-link-api-001"
               }
             ]
           } = json_response(link_assignments_conn, 200)

    unmatched_link_assignments_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/link_assignments?source_endpoint_ref=missing-source"
      )

    assert %{"data" => []} = json_response(unmatched_link_assignments_conn, 200)

    link_assignment_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/link_assignments/link-assignment-api-001"
      )

    assert %{"data" => %{"link_assignment_id" => "link-assignment-api-001"}} =
             json_response(link_assignment_show_conn, 200)

    scheduled_contact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts",
        %{
          "scheduled_contact" => %{
            "scheduled_contact_id" => "link-assignment-contact-api-001",
            "contact_intents" => ["telemetry_downlink"],
            "link_assignment_refs" => [
              %{"link_assignment_id" => "link-assignment-api-001"}
            ],
            "starts_at" => "2026-03-30T18:00:00Z",
            "ends_at" => "2026-03-30T18:10:00Z"
          }
        }
      )

    assert %{
             "data" => %{
               "scheduled_contact_id" => "link-assignment-contact-api-001",
               "source_endpoint_refs" => ["source-endpoint-link-api-001"],
               "contact_intents" => ["telemetry_downlink"],
               "link_assignment_refs" => [
                 %{"link_assignment_id" => "link-assignment-api-001"}
               ]
             }
           } = json_response(scheduled_contact_conn, 201)

    realized_link_assignment_contact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts/link-assignment-contact-api-001/realize",
        %{"realization" => %{"clock_mode" => "replay"}}
      )

    assert %{
             "data" => %{
               "realized_contact_id" => "link-assignment-contact-api-001_run",
               "source_endpoint_refs" => ["source-endpoint-link-api-001"],
               "contact_intents" => ["telemetry_downlink"],
               "paths" => [
                 %{
                   "path_id" => "link-assignment-api-001",
                   "source_endpoint_ref" => "source-endpoint-link-api-001",
                   "provider_path_ref" => "provider-path-link-api-001",
                   "metadata" => %{
                     "link_assignment_id" => "link-assignment-api-001",
                     "path_template_id" => "downlink-link-api-template",
                     "path_template_version" => 2,
                     "spacecraft_id" => "spacecraft-link-api-001"
                   }
                 }
               ],
               "metadata" => %{
                 "contact_intents" => ["telemetry_downlink"],
                 "link_assignment_refs" => [
                   %{"link_assignment_id" => "link-assignment-api-001"}
                 ]
               }
             }
           } = json_response(realized_link_assignment_contact_conn, 200)

    invalid_command_window_contact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts",
        %{
          "scheduled_contact" => %{
            "scheduled_contact_id" => "invalid-command-window-contact",
            "contact_intents" => ["command_window"],
            "link_assignment_refs" => [
              %{"link_assignment_id" => "link-assignment-api-001"}
            ],
            "starts_at" => "2026-03-30T19:00:00Z",
            "ends_at" => "2026-03-30T19:10:00Z"
          }
        }
      )

    assert %{"errors" => [%{"reason" => "scheduled_contact_requires_selected_uplink_path"}]} =
             json_response(invalid_command_window_contact_conn, 422)

    invalid_selected_path_contact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/scheduled_contacts",
        %{
          "scheduled_contact" => %{
            "scheduled_contact_id" => "invalid-selected-path-contact",
            "contact_intents" => ["maintenance"],
            "paths" => [
              %{
                "path_id" => "candidate-only-path",
                "direction" => "downlink",
                "selection_role" => "candidate",
                "source_endpoint_ref" => "source-endpoint-link-api-001"
              }
            ],
            "starts_at" => "2026-03-30T19:30:00Z",
            "ends_at" => "2026-03-30T19:40:00Z"
          }
        }
      )

    assert %{"errors" => [%{"reason" => "scheduled_contact_requires_selected_path"}]} =
             json_response(invalid_selected_path_contact_conn, 422)

    link_assignment_delete_conn =
      conn
      |> authorize(api_token)
      |> delete(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/link_assignments/link-assignment-api-001",
        %{"link_assignment" => %{"metadata" => %{"deleted_by" => "api-test"}}}
      )

    assert %{
             "data" => %{
               "link_assignment_id" => "link-assignment-api-001",
               "lifecycle_state" => "deleted",
               "metadata" => %{
                 "display_name" => "SC Link API downlink",
                 "deleted_by" => "api-test"
               }
             }
           } = json_response(link_assignment_delete_conn, 200)

    missing_link_assignment_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/link_assignments/link-assignment-api-001"
      )

    assert %{"errors" => [%{"reason" => "contact_link_assignment_not_found"}]} =
             json_response(missing_link_assignment_conn, 404)
  end

  test "mission-scoped token is constrained to its mission", %{conn: conn} do
    %{conn: conn, api_token: org_api_token, organization_id: organization_id} = bootstrap(conn)

    conn
    |> authorize(org_api_token)
    |> post("/api/organizations/#{organization_id}/missions", %{
      "mission" => %{
        "mission_id" => "mission-bravo",
        "slug" => "mission-bravo",
        "display_name" => "Mission Bravo"
      }
    })

    mission_identity_conn =
      conn
      |> authorize(org_api_token)
      |> post("/api/organizations/#{organization_id}/service_identities", %{
        "service_identity" => %{
          "service_identity_id" => "svc-mission",
          "mission_id" => "mission-bravo",
          "display_name" => "Mission Bravo Service",
          "capabilities" => ["mission_admin"]
        }
      })

    assert %{
             "data" => %{
               "service_identity" => %{
                 "service_identity_id" => "svc-mission",
                 "mission_id" => "mission-bravo",
                 "capabilities" => ["mission_admin"]
               },
               "api_token" => mission_api_token
             }
           } = json_response(mission_identity_conn, 201)

    allowed_conn =
      conn
      |> authorize(mission_api_token)
      |> get("/api/organizations/#{organization_id}/missions/mission-bravo")

    assert %{"data" => %{"mission_id" => "mission-bravo"}} = json_response(allowed_conn, 200)

    forbidden_conn =
      conn
      |> authorize(mission_api_token)
      |> get("/api/organizations/#{organization_id}/missions/mission-alpha")

    assert %{"errors" => [%{"reason" => "forbidden"}]} = json_response(forbidden_conn, 403)
  end

  test "authenticated mission read endpoints expose mission health and mission events", %{
    conn: conn
  } do
    %{conn: conn, api_token: api_token, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    seed_mission_read_models(organization_id, mission_id)

    mission_health_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/mission_health")

    assert %{
             "data" => %{
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "total_points" => 2,
               "violating_points" => 1,
               "worst_normalized_state" => "yellow",
               "normalized_state_counts" => %{
                 "red" => 0,
                 "yellow" => 1,
                 "green" => 1,
                 "blue" => 0
               },
               "scope_summaries" => [
                 %{
                   "scope_kind" => "spacecraft",
                   "spacecraft_id" => "spacecraft-001",
                   "total_points" => 2,
                   "violating_points" => 1
                 }
               ]
             }
           } = json_response(mission_health_conn, 200)

    spacecraft_health_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/mission_health?spacecraft_id=spacecraft-001"
      )

    assert %{
             "data" => %{
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "total_points" => 2,
               "violating_points" => 1,
               "scope_summaries" => [
                 %{
                   "scope_kind" => "spacecraft",
                   "spacecraft_id" => "spacecraft-001"
                 }
               ]
             }
           } = json_response(spacecraft_health_conn, 200)

    mission_events_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/mission_events?category=health&limit=10"
      )

    assert %{
             "data" => [
               %{
                 "organization_id" => ^organization_id,
                 "mission_id" => ^mission_id,
                 "category" => "health",
                 "kind" => "limit_violation",
                 "severity" => "warning",
                 "subject_kind" => "telemetry_point",
                 "subject_id" => "HK.counter"
               }
             ]
           } = json_response(mission_events_conn, 200)

    all_mission_events_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/mission_events")

    assert %{
             "data" => mission_events
           } = json_response(all_mission_events_conn, 200)

    assert Enum.any?(mission_events, &(&1["kind"] == "scheduled_contact_canceled"))
    assert Enum.any?(mission_events, &(&1["kind"] == "limit_violation"))
  end
end
