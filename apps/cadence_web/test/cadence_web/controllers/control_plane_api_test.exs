defmodule CadenceWeb.ControlPlaneApiTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.CCSDS.Core.SDUOctets
  alias Cadence.CCSDS.SDLP.TM.Segmentation
  alias Cadence.Jobs
  alias Cadence.Contacts.{Path, RealizedContact, ScheduledContact, TransportBinding}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Limits.Definition, as: LimitDefinition
  alias Cadence.Spacecraft
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.PacketDefinition

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

    assert {:ok, _user} = Cadence.ensure_bootstrap_admin()

    on_exit(fn ->
      Application.put_env(:cadence, :catalog_importers, previous_importers)
      Application.put_env(:cadence, :bootstrap_admin, previous_bootstrap_admin)
    end)

    :ok
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
            "source_endpoint_refs" => ["source-endpoint-001"],
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
            "source_endpoint_refs" => ["source-endpoint-001"],
            "path_template_ids" => ["downlink-template-versioned"],
            "starts_at" => "2026-03-30T18:00:00Z",
            "ends_at" => "2026-03-30T18:10:00Z"
          }
        }
      )

    assert %{
             "data" => %{
               "scheduled_contact_id" => "contact-versioned",
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

  test "authenticated mission API manages catalog artifacts and import runs", %{conn: conn} do
    %{conn: conn, api_token: api_token, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    importers_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/catalog/importers")

    assert %{
             "data" => [
               %{
                 "importer_key" => "fake_tm_json",
                 "catalog_family" => "telemetry"
               }
             ]
           } = json_response(importers_conn, 200)

    artifact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_artifacts",
        %{
          "catalog_artifact" => %{
            "artifact_id" => "artifact-alpha",
            "catalog_family" => "telemetry",
            "artifact_name" => "mission-alpha-tm.json",
            "format_key" => "fake_tm_json",
            "media_type" => "application/json",
            "source_artifact" => %{
              "packets" => [
                %{"name" => "HK_PACKET"},
                %{"name" => "EVENT_PACKET"}
              ]
            }
          }
        }
      )

    assert %{
             "data" => %{
               "artifact_id" => "artifact-alpha",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "catalog_family" => "telemetry",
               "format_key" => "fake_tm_json",
               "content_sha256" => content_sha256,
               "uploaded_by" => %{
                 "service_identity_id" => "svc-bootstrap"
               }
             }
           } = json_response(artifact_conn, 201)

    assert is_binary(content_sha256)
    assert content_sha256 != ""

    listed_artifacts_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_artifacts?catalog_family=telemetry"
      )

    assert %{
             "data" => [
               %{
                 "artifact_id" => "artifact-alpha",
                 "catalog_family" => "telemetry"
               }
             ]
           } = json_response(listed_artifacts_conn, 200)

    import_run_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs",
        %{
          "catalog_import_run" => %{
            "artifact_id" => "artifact-alpha",
            "importer_key" => "fake_tm_json",
            "metadata" => %{"reason" => "bootstrap"}
          }
        }
      )

    assert %{
             "data" => %{
               "import_run_id" => import_run_id,
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id,
               "artifact_id" => "artifact-alpha",
               "importer_key" => "fake_tm_json",
               "status" => "running",
               "requested_by" => %{
                 "service_identity_id" => "svc-bootstrap"
               }
             }
           } = json_response(import_run_conn, 201)

    assert [{:ok, claimed_job}] =
             Jobs.claim_jobs(1)
             |> Enum.map(fn job -> {:ok, job} end)

    assert {:ok, _completed_job} = Jobs.run_job(claimed_job.job_id)

    import_run_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs/#{import_run_id}"
      )

    assert %{
             "data" => %{
               "import_run_id" => ^import_run_id,
               "snapshot_id" => snapshot_id,
               "status" => "completed",
               "imported_definition_count" => 2,
               "diagnostics" => [
                 %{
                   "code" => "fake_tm_json.warning",
                   "severity" => "warning"
                 }
               ],
               "result_document" => %{
                 "snapshot" => snapshot_document,
                 "packet_names" => ["HK_PACKET", "EVENT_PACKET"]
               }
             }
           } = json_response(import_run_show_conn, 200)

    assert snapshot_document["snapshot_id"] == snapshot_id

    listed_import_runs_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs?status=completed&artifact_id=artifact-alpha"
      )

    assert %{
             "data" => [
               %{
                 "import_run_id" => ^import_run_id,
                 "snapshot_id" => ^snapshot_id,
                 "status" => "completed",
                 "artifact_id" => "artifact-alpha"
               }
             ]
           } = json_response(listed_import_runs_conn, 200)

    listed_snapshots_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_telemetry_snapshots?import_run_id=#{import_run_id}"
      )

    assert %{
             "data" => [
               %{
                 "snapshot_id" => ^snapshot_id,
                 "artifact_id" => "artifact-alpha",
                 "packet_count" => 2
               }
             ]
           } = json_response(listed_snapshots_conn, 200)

    snapshot_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_telemetry_snapshots/#{snapshot_id}"
      )

    assert %{
             "data" => %{
               "snapshot_id" => ^snapshot_id,
               "snapshot_name" => "mission-alpha-tm.json",
               "packet_count" => 2,
               "snapshot_document" => %{
                 "snapshot_id" => ^snapshot_id,
                 "packets" => [
                   %{"name" => "HK_PACKET"},
                   %{"name" => "EVENT_PACKET"}
                 ]
               }
             }
           } = json_response(snapshot_show_conn, 200)
  end

  test "authenticated mission API recompiles telemetry snapshots, materializes runtime artifacts, and ingests dev space packets",
       %{
         conn: conn
       } do
    Application.put_env(:cadence, :catalog_importers, [
      Cadence.Catalog.Importers.CadenceYamlDatabase
    ])

    %{conn: conn, api_token: api_token, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    artifact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_artifacts",
        %{
          "catalog_artifact" => %{
            "artifact_id" => "artifact-yaml-alpha",
            "catalog_family" => "combined",
            "artifact_name" => "mission-alpha-dev.yaml",
            "format_key" => "cadence_yaml",
            "media_type" => "application/yaml",
            "source_artifact" => %{
              "yaml" => """
              version: "1.0.0"

              packets:
                - name: THERM
                  apid: 42
                  items:
                    - name: temperature_c
                      bit_offset: 0
                      bit_size: 32
                      data_type: float
                      endianness: big
                    - name: heater_enabled
                      bit_offset: 32
                      bit_size: 1
                      data_type: bool

              commands:
                - name: NOOP
                  opcode: 0x01
              """
            }
          }
        }
      )

    assert %{"data" => %{"artifact_id" => "artifact-yaml-alpha"}} =
             json_response(artifact_conn, 201)

    import_run_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs",
        %{
          "catalog_import_run" => %{
            "artifact_id" => "artifact-yaml-alpha",
            "importer_key" => "cadence_yaml"
          }
        }
      )

    assert %{"data" => %{"import_run_id" => import_run_id}} = json_response(import_run_conn, 201)

    assert [{:ok, claimed_job}] =
             Jobs.claim_jobs(1)
             |> Enum.map(fn job -> {:ok, job} end)

    assert {:ok, _completed_job} = Jobs.run_job(claimed_job.job_id)

    import_run_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs/#{import_run_id}"
      )

    assert %{
             "data" => %{
               "snapshot_id" => snapshot_id,
               "result_document" => %{
                 "command_snapshot" => %{"snapshot_id" => command_snapshot_id}
               }
             }
           } = json_response(import_run_show_conn, 200)

    command_snapshot_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_command_snapshots/#{command_snapshot_id}"
      )

    assert %{
             "data" => %{
               "snapshot_id" => ^command_snapshot_id,
               "command_count" => 1,
               "snapshot_document" => %{
                 "snapshot_id" => ^command_snapshot_id
               }
             }
           } = json_response(command_snapshot_conn, 200)

    command_compile_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_command_snapshots/#{command_snapshot_id}/compile"
      )

    assert %{
             "data" => %{
               "snapshot" => %{"snapshot_id" => ^command_snapshot_id, "command_count" => 1},
               "compiler_result" => %{
                 "runtime_definition_count" => 1,
                 "diagnostic_count" => 0
               }
             }
           } = json_response(command_compile_conn, 200)

    recompile_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_telemetry_snapshots/#{snapshot_id}/recompile"
      )

    assert %{
             "data" => %{
               "snapshot" => %{"snapshot_id" => ^snapshot_id, "packet_count" => 1},
               "compiler_result" => %{
                 "packet_definition_count" => 1,
                 "selector_input_count" => 1,
                 "diagnostic_count" => 0
               },
               "binding_set" => %{
                 "binding_set_id" => binding_set_id,
                 "version" => 1,
                 "capability_instance_count" => 1,
                 "rule_count" => 1
               }
             }
           } = json_response(recompile_conn, 200)

    assert binding_set_id == "catalog_import:" <> import_run_id

    runtime_diff_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_telemetry_snapshots/#{snapshot_id}/runtime_diff"
      )

    assert %{
             "data" => %{
               "snapshot_id" => ^snapshot_id,
               "existing_binding_set" => %{"binding_set_id" => ^binding_set_id, "version" => 1},
               "packet_definitions" => %{
                 "matching_count" => 1,
                 "mismatches" => [],
                 "missing_existing" => [],
                 "extra_existing" => []
               },
               "capability_instances" => %{
                 "matching_count" => 1,
                 "mismatches" => []
               },
               "binding_rules" => %{
                 "matching_count" => 1,
                 "mismatches" => []
               }
             }
           } = json_response(runtime_diff_conn, 200)

    materialize_runtime_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_telemetry_snapshots/#{snapshot_id}/materialize_runtime",
        %{}
      )

    assert %{
             "data" => %{
               "snapshot" => %{"snapshot_id" => ^snapshot_id},
               "compiler_result" => %{
                 "packet_definition_count" => 1,
                 "selector_input_count" => 1,
                 "diagnostic_count" => 0
               },
               "binding_set" => %{
                 "binding_set_id" => ^binding_set_id,
                 "version" => 2,
                 "capability_instance_count" => 1,
                 "rule_count" => 1
               }
             }
           } = json_response(materialize_runtime_conn, 201)

    runtime_diff_after_materialization_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_telemetry_snapshots/#{snapshot_id}/runtime_diff"
      )

    assert %{
             "data" => %{
               "snapshot_id" => ^snapshot_id,
               "existing_binding_set" => %{"binding_set_id" => ^binding_set_id, "version" => 2},
               "packet_definitions" => %{
                 "matching_count" => 1,
                 "mismatches" => [],
                 "missing_existing" => [],
                 "extra_existing" => []
               },
               "capability_instances" => %{
                 "matching_count" => 1,
                 "mismatches" => []
               },
               "binding_rules" => %{
                 "matching_count" => 1,
                 "mismatches" => []
               }
             }
           } = json_response(runtime_diff_after_materialization_conn, 200)

    activation_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/activations", %{
        "activation" => %{
          "binding_set_id" => binding_set_id,
          "version" => 2
        }
      })

    assert %{
             "data" => %{
               "binding_set_id" => ^binding_set_id,
               "binding_set_version" => 2
             }
           } = json_response(activation_conn, 201)

    packet_hex =
      build_space_packet(42, 3, <<12.5::float-32, 1::size(1), 0::size(7)>>)
      |> Base.encode16(case: :lower)

    dev_ingress_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/dev/space_packets", %{
        "space_packet" => %{
          "source_ref" => "station-a",
          "packet_hex" => packet_hex
        }
      })

    assert %{
             "data" => %{
               "raw_evidence" => %{
                 "mission_id" => ^mission_id,
                 "protocol_family" => "space_packet",
                 "direction" => "downlink",
                 "source_ref" => "station-a",
                 "raw_hex" => ^packet_hex
               },
               "packet_records" => [
                 %{
                   "mission_id" => ^mission_id,
                   "packet_kind" => "space_packet",
                   "apid" => 42,
                   "sequence_count" => 3,
                   "secondary_header" => false
                 }
               ],
               "dispatch_decisions" => [
                 %{
                   "binding_set_id" => ^binding_set_id,
                   "binding_set_version" => 2,
                   "status" => "matched"
                 }
               ],
               "outputs" => [
                 %{
                   "output_kind" => "telemetry_sample",
                   "point_name" => "THERM.temperature_c",
                   "raw_value" => 12.5,
                   "engineering_value" => 12.5
                 },
                 %{
                   "output_kind" => "telemetry_sample",
                   "point_name" => "THERM.heater_enabled",
                   "raw_value" => true,
                   "engineering_value" => true
                 }
               ]
             }
           } = json_response(dev_ingress_conn, 200)

    frame_size = 17

    tm_frame_hex =
      build_tm_single_frame(
        42,
        4,
        <<12.5::float-32, 1::size(1), 0::size(7)>>,
        frame_size
      )
      |> Base.encode16(case: :lower)

    dev_tm_ingress_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/dev/tm_frames", %{
        "tm_frame" => %{
          "source_ref" => "station-b",
          "frame_hex" => tm_frame_hex,
          "frame_size" => frame_size,
          "ocf_length" => 0
        }
      })

    assert %{
             "data" => %{
               "raw_evidence" => %{
                 "mission_id" => ^mission_id,
                 "protocol_family" => "tm_transfer_frame",
                 "direction" => "downlink",
                 "source_ref" => "station-b",
                 "raw_hex" => ^tm_frame_hex
               },
               "transfer_frame_records" => [
                 %{
                   "mission_id" => ^mission_id,
                   "protocol_family" => "tm_transfer_frame",
                   "scid" => 11,
                   "vcid" => 2,
                   "frame_seq" => 0,
                   "raw_frame_length_bytes" => ^frame_size
                 }
               ],
               "protocol_anomalies" => [],
               "packet_records" => [
                 %{
                   "mission_id" => ^mission_id,
                   "packet_kind" => "space_packet",
                   "apid" => 42,
                   "sequence_count" => 4,
                   "secondary_header" => false
                 }
               ],
               "dispatch_decisions" => [
                 %{
                   "binding_set_id" => ^binding_set_id,
                   "binding_set_version" => 2,
                   "status" => "matched"
                 }
               ],
               "outputs" => [
                 %{
                   "output_kind" => "telemetry_sample",
                   "point_name" => "THERM.temperature_c",
                   "raw_value" => 12.5,
                   "engineering_value" => 12.5
                 },
                 %{
                   "output_kind" => "telemetry_sample",
                   "point_name" => "THERM.heater_enabled",
                   "raw_value" => true,
                   "engineering_value" => true
                 }
               ]
             }
           } = json_response(dev_tm_ingress_conn, 200)

    latest_values_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/telemetry/latest")

    assert %{
             "data" => [
               %{
                 "point_id" => "THERM.heater_enabled",
                 "point_name" => "THERM.heater_enabled",
                 "engineering_value" => true
               },
               %{
                 "point_id" => "THERM.temperature_c",
                 "point_name" => "THERM.temperature_c",
                 "engineering_value" => 12.5
               }
             ]
           } = json_response(latest_values_conn, 200)

    latest_value_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/telemetry/points/THERM.temperature_c/latest"
      )

    assert %{
             "data" => %{
               "point_id" => "THERM.temperature_c",
               "point_name" => "THERM.temperature_c",
               "raw_value" => 12.5,
               "engineering_value" => 12.5
             }
           } = json_response(latest_value_conn, 200)

    history_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/telemetry/points/THERM.temperature_c/history?limit=10&order=desc"
      )

    assert %{
             "data" => [
               %{
                 "point_id" => "THERM.temperature_c",
                 "point_name" => "THERM.temperature_c",
                 "raw_value" => 12.5,
                 "engineering_value" => 12.5
               },
               %{
                 "point_id" => "THERM.temperature_c",
                 "point_name" => "THERM.temperature_c",
                 "raw_value" => 12.5,
                 "engineering_value" => 12.5
               }
             ]
           } = json_response(history_conn, 200)
  end

  test "authenticated mission API manages command stages, requests, approvals, and queue entries",
       %{conn: conn} do
    Application.put_env(:cadence, :catalog_importers, [
      Cadence.Catalog.Importers.CadenceYamlDatabase
    ])

    %{conn: conn, api_token: api_token, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    spacecraft_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft", %{
        "spacecraft" => %{
          "spacecraft_id" => "spacecraft-commanding-001",
          "display_name" => "SC-CMD-001"
        }
      })

    assert %{"data" => %{"spacecraft_id" => "spacecraft-commanding-001"}} =
             json_response(spacecraft_conn, 201)

    source_endpoint_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft/spacecraft-commanding-001/source_endpoints",
        %{
          "source_endpoint" => %{
            "source_endpoint_id" => "source-endpoint-commanding-001",
            "source_ref" => "sc-cmd-001",
            "display_name" => "SC Commanding Endpoint"
          }
        }
      )

    assert %{"data" => %{"source_endpoint_id" => "source-endpoint-commanding-001"}} =
             json_response(source_endpoint_conn, 201)

    artifact_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_artifacts",
        %{
          "catalog_artifact" => %{
            "artifact_id" => "artifact-commanding-api",
            "artifact_name" => "commanding-api.yaml",
            "catalog_family" => "combined",
            "format_key" => "cadence_yaml",
            "media_type" => "application/yaml",
            "source_artifact" => """
            version: "1.0.0"

            commands:
              - name: NOOP
                opcode: 0x01
                parameters: []
              - name: SET_MODE
                opcode: 0x03
                is_hazardous: true
                hazard_description: "Mode changes affect safing behavior"
                requires_confirmation: true
                parameters:
                  - name: mode
                    data_type: uint
                    required: true
                    bit_offset: 0
                    bit_length: 8
                  - name: delay_s
                    data_type: uint
                    required: false
                    default_value: 5
                    bit_offset: 8
                    bit_length: 8
                verifiers:
                  - name: Release Accepted
                    phase: acceptance
                    timeout_ms: 1000
                    success_criteria:
                      criteria_type: comparison
                      subject_ref: transport:accepted
                      comparison: equal
                      value: true
                  - name: Mode Applied
                    phase: completion
                    timeout_ms: 5000
                    success_criteria:
                      criteria_type: comparison
                      subject_ref: mode_state
                      comparison: equal
                      value: 3
            """
          }
        }
      )

    assert %{"data" => %{"artifact_id" => "artifact-commanding-api"}} =
             json_response(artifact_conn, 201)

    import_run_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs",
        %{
          "catalog_import_run" => %{
            "artifact_id" => "artifact-commanding-api",
            "importer_key" => "cadence_yaml"
          }
        }
      )

    assert %{"data" => %{"import_run_id" => import_run_id}} = json_response(import_run_conn, 201)

    assert [{:ok, claimed_job}] =
             Jobs.claim_jobs(1)
             |> Enum.map(fn job -> {:ok, job} end)

    assert {:ok, _completed_job} = Jobs.run_job(claimed_job.job_id)

    import_run_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs/#{import_run_id}"
      )

    assert %{
             "data" => %{
               "result_document" => %{
                 "command_snapshot" => %{"snapshot_id" => command_snapshot_id}
               }
             }
           } = json_response(import_run_show_conn, 200)

    assert {:ok, command_snapshot} =
             Cadence.fetch_catalog_command_snapshot(
               organization_id,
               mission_id,
               command_snapshot_id
             )

    noop_command_id = fetch_command_id(command_snapshot, "NOOP")
    set_mode_command_id = fetch_command_id(command_snapshot, "SET_MODE")

    command_stage_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/command_stages", %{
        "command_stage" => %{
          "command_stage_id" => "command-stage-alpha",
          "stage_name" => "Pass Review",
          "description" => "Review before uplink",
          "visibility" => "shared"
        }
      })

    assert %{
             "data" => %{
               "command_stage_id" => "command-stage-alpha",
               "lifecycle_state" => "draft",
               "visibility" => "shared"
             }
           } = json_response(command_stage_conn, 201)

    updated_command_stage_conn =
      conn
      |> authorize(api_token)
      |> patch(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_stages/command-stage-alpha",
        %{
          "command_stage" => %{
            "lifecycle_state" => "in_review"
          }
        }
      )

    assert %{"data" => %{"lifecycle_state" => "in_review"}} =
             json_response(updated_command_stage_conn, 200)

    staged_command_item_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_stages/command-stage-alpha/items",
        %{
          "staged_command_item" => %{
            "staged_command_item_id" => "staged-command-item-alpha",
            "source_endpoint_ref" => "source-endpoint-commanding-001",
            "command_snapshot_id" => command_snapshot_id,
            "command_id" => set_mode_command_id,
            "argument_values" => %{"mode" => 2},
            "priority" => 2,
            "item_order" => 0,
            "notes" => "Initial draft"
          }
        }
      )

    assert %{
             "data" => %{
               "staged_command_item_id" => "staged-command-item-alpha",
               "lifecycle_state" => "draft",
               "argument_values" => %{"mode" => 2}
             }
           } = json_response(staged_command_item_conn, 201)

    updated_staged_command_item_conn =
      conn
      |> authorize(api_token)
      |> patch(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/staged_command_items/staged-command-item-alpha",
        %{
          "staged_command_item" => %{
            "argument_values" => %{"mode" => 3},
            "notes" => "Reviewed by FDO"
          }
        }
      )

    assert %{
             "data" => %{
               "argument_values" => %{"mode" => 3},
               "notes" => "Reviewed by FDO"
             }
           } = json_response(updated_staged_command_item_conn, 200)

    staged_command_items_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_stages/command-stage-alpha/items"
      )

    assert %{
             "data" => [
               %{
                 "staged_command_item_id" => "staged-command-item-alpha",
                 "argument_values" => %{"mode" => 3}
               }
             ]
           } = json_response(staged_command_items_conn, 200)

    submitted_command_requests_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_stages/command-stage-alpha/submit",
        %{
          "submission" => %{
            "staged_command_item_ids" => ["staged-command-item-alpha"],
            "requested_by" => %{"user_id" => "requester-1"}
          }
        }
      )

    assert %{
             "data" => [
               %{
                 "command_request_id" => staged_command_request_id,
                 "lifecycle_state" => "approval_pending",
                 "source_command_stage_id" => "command-stage-alpha",
                 "source_staged_command_item_id" => "staged-command-item-alpha"
               }
             ]
           } = json_response(submitted_command_requests_conn, 200)

    command_requests_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_requests",
        %{"command_stage_id" => "command-stage-alpha"}
      )

    assert %{
             "data" => [
               %{
                 "command_request_id" => ^staged_command_request_id,
                 "lifecycle_state" => "approval_pending"
               }
             ]
           } = json_response(command_requests_conn, 200)

    approved_command_request_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_requests/#{staged_command_request_id}/approve",
        %{
          "approval" => %{
            "decided_by" => %{"user_id" => "reviewer-1"},
            "reason" => "Reviewed for uplink"
          }
        }
      )

    approved_command_request_response = json_response(approved_command_request_conn, 200)

    assert %{
             "data" => %{
               "approval" => %{
                 "command_approval_id" => command_approval_id,
                 "command_request_id" => ^staged_command_request_id,
                 "decision" => "approved",
                 "reason" => "Reviewed for uplink"
               },
               "command_request" => %{
                 "command_request_id" => ^staged_command_request_id,
                 "lifecycle_state" => "approved"
               }
             }
           } = approved_command_request_response

    command_approvals_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_approvals",
        %{"command_request_id" => staged_command_request_id}
      )

    assert %{
             "data" => [
               %{
                 "command_approval_id" => ^command_approval_id,
                 "decision" => "approved"
               }
             ]
           } = json_response(command_approvals_conn, 200)

    command_queue_entry_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_requests/#{staged_command_request_id}/enqueue",
        %{
          "queue_entry" => %{
            "enqueued_by" => %{"user_id" => "queue-operator"}
          }
        }
      )

    assert %{
             "data" => %{
               "queue_entry" => %{
                 "command_queue_entry_id" => staged_queue_entry_id,
                 "queue_lane_key" => "source-endpoint-commanding-001",
                 "priority" => 2
               },
               "command_request" => %{
                 "command_request_id" => ^staged_command_request_id,
                 "lifecycle_state" => "queued"
               }
             }
           } = json_response(command_queue_entry_conn, 200)

    direct_command_request_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/command_requests", %{
        "command_request" => %{
          "command_request_id" => "command-request-noop",
          "source_endpoint_ref" => "source-endpoint-commanding-001",
          "command_snapshot_id" => command_snapshot_id,
          "command_id" => noop_command_id,
          "priority" => 1,
          "requested_by" => %{"user_id" => "requester-2"}
        }
      })

    assert %{
             "data" => %{
               "command_request_id" => "command-request-noop",
               "lifecycle_state" => "validated"
             }
           } = json_response(direct_command_request_conn, 201)

    noop_queue_entry_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_requests/command-request-noop/enqueue",
        %{
          "queue_entry" => %{
            "enqueued_by" => %{"user_id" => "queue-operator"}
          }
        }
      )

    assert %{
             "data" => %{
               "queue_entry" => %{
                 "command_queue_entry_id" => noop_queue_entry_id,
                 "priority" => 1
               }
             }
           } = json_response(noop_queue_entry_conn, 200)

    command_queue_entries_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_queue_entries",
        %{"queue_lane_key" => "source-endpoint-commanding-001"}
      )

    assert %{
             "data" => [
               %{"command_queue_entry_id" => ^noop_queue_entry_id, "priority" => 1},
               %{"command_queue_entry_id" => ^staged_queue_entry_id, "priority" => 2}
             ]
           } = json_response(command_queue_entries_conn, 200)

    realized_contact =
      persist_active_uplink_contact_for_command_release(
        organization_id,
        mission_id,
        "source-endpoint-commanding-001"
      )

    release_queue_entry_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_queue_entries/#{noop_queue_entry_id}/release",
        %{
          "release_attempt" => %{
            "realized_contact_id" => realized_contact.realized_contact_id,
            "released_by" => %{"user_id" => "release-operator"}
          }
        }
      )

    assert %{
             "data" => %{
               "release_attempt" => %{
                 "command_release_attempt_id" => command_release_attempt_id,
                 "command_queue_entry_id" => ^noop_queue_entry_id,
                 "realized_contact_id" => realized_contact_id,
                 "path_id" => "uplink-path-commanding-api",
                 "transport_binding_id" => "uplink-gateway-commanding-api",
                 "lifecycle_state" => "released",
                 "verification_state" => "not_required",
                 "encoded_binary_base64" => encoded_binary_base64
               },
               "queue_entry" => %{
                 "command_queue_entry_id" => ^noop_queue_entry_id,
                 "lifecycle_state" => "released"
               },
               "command_request" => %{
                 "command_request_id" => "command-request-noop",
                 "lifecycle_state" => "released",
                 "verification_state" => "not_required"
               }
             }
           } = json_response(release_queue_entry_conn, 200)

    assert realized_contact_id == realized_contact.realized_contact_id
    assert Base.decode64!(encoded_binary_base64) == <<0x01>>

    command_release_attempts_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_release_attempts",
        %{"command_queue_entry_id" => noop_queue_entry_id}
      )

    assert %{
             "data" => [
               %{
                 "command_release_attempt_id" => ^command_release_attempt_id,
                 "command_queue_entry_id" => ^noop_queue_entry_id,
                 "lifecycle_state" => "released"
               }
             ]
           } = json_response(command_release_attempts_conn, 200)

    command_release_attempt_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_release_attempts/#{command_release_attempt_id}"
      )

    assert %{
             "data" => %{
               "command_release_attempt_id" => ^command_release_attempt_id,
               "transport_binding_id" => "uplink-gateway-commanding-api",
               "lifecycle_state" => "released",
               "verification_state" => "not_required"
             }
           } = json_response(command_release_attempt_conn, 200)

    staged_release_queue_entry_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_queue_entries/#{staged_queue_entry_id}/release",
        %{
          "release_attempt" => %{
            "realized_contact_id" => realized_contact.realized_contact_id,
            "released_by" => %{"user_id" => "release-operator"}
          }
        }
      )

    assert %{
             "data" => %{
               "release_attempt" => %{
                 "command_queue_entry_id" => ^staged_queue_entry_id,
                 "lifecycle_state" => "released",
                 "verification_state" => "pending"
               },
               "command_request" => %{
                 "command_request_id" => ^staged_command_request_id,
                 "verification_state" => "pending"
               }
             }
           } = json_response(staged_release_queue_entry_conn, 200)

    command_verifier_instances_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/command_verifier_instances",
        %{"command_request_id" => staged_command_request_id}
      )

    assert %{"data" => command_verifier_instances} =
             json_response(command_verifier_instances_conn, 200)

    assert length(command_verifier_instances) == 2

    assert %{
             "command_request_id" => ^staged_command_request_id,
             "verifier_name" => "Release Accepted",
             "phase" => "acceptance",
             "lifecycle_state" => "satisfied",
             "matched_record_kind" => "transport_action_request"
           } = Enum.find(command_verifier_instances, &(&1["phase"] == "acceptance"))

    assert %{
             "command_request_id" => ^staged_command_request_id,
             "verifier_name" => "Mode Applied",
             "phase" => "completion",
             "lifecycle_state" => "pending"
           } = Enum.find(command_verifier_instances, &(&1["phase"] == "completion"))
  end

  defp bootstrap(conn) do
    bootstrap_admin_token = bootstrap_admin_login(conn)

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

    %{
      "data" => %{
        "organization" => %{"organization_id" => organization_id},
        "mission" => %{"mission_id" => mission_id},
        "service_identity" => %{"api_token" => api_token}
      }
    } = json_response(bootstrap_conn, 201)

    %{
      conn: conn,
      api_token: api_token,
      organization_id: organization_id,
      mission_id: mission_id
    }
  end

  defp bootstrap_admin_login(conn) do
    login_conn =
      post(conn, "/api/bootstrap_admin/login", %{
        "bootstrap_admin_session" => %{
          "email" => @bootstrap_admin_email,
          "password" => @bootstrap_admin_password
        }
      })

    %{"data" => %{"session_token" => session_token}} = json_response(login_conn, 201)
    session_token
  end

  defp authorize(conn, api_token) do
    put_req_header(conn, "authorization", "Bearer " <> api_token)
  end

  defp fetch_command_id(command_snapshot, command_name) do
    command_snapshot.command_definitions
    |> Enum.find(&(&1.name == command_name))
    |> then(& &1.command_id)
  end

  defp seed_mission_read_models(organization_id, mission_id) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "spacecraft-001",
        organization_id: organization_id,
        mission_id: mission_id,
        display_name: "SC-001"
      })

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "source-endpoint-read-models",
        organization_id: organization_id,
        mission_id: mission_id,
        spacecraft_id: "spacecraft-001",
        source_ref: "sc-001",
        display_name: "SC-001"
      })

    packet_definition =
      PacketDefinition.new(%{
        packet_definition_id: "packet-def-read-models",
        organization_id: organization_id,
        mission_id: mission_id,
        packet_name: "HK",
        apid: 42,
        fields: [
          %{
            field_id: "field-counter",
            name: "counter",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          },
          %{
            field_id: "field-voltage",
            name: "voltage",
            offset_bits: 16,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        binding_set_id: "read-models",
        organization_id: organization_id,
        mission_id: mission_id,
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "tm-apid-42",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    counter_limit =
      LimitDefinition.new(%{
        mission_id: mission_id,
        limit_definition_id: "counter-limit-read-models",
        point_id: "HK.counter",
        limit_set_name: "ops",
        thresholds: %{"yellow_high" => 20}
      })

    voltage_limit =
      LimitDefinition.new(%{
        mission_id: mission_id,
        limit_definition_id: "voltage-limit-read-models",
        point_id: "HK.voltage",
        limit_set_name: "ops",
        thresholds: %{"yellow_high" => 100}
      })

    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: "scheduled-contact-read-models",
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: [source_endpoint.source_endpoint_id],
        starts_at: DateTime.from_unix!(1_700_090_000, :second),
        ends_at: DateTime.from_unix!(1_700_090_600, :second),
        paths: contact_paths(source_endpoint.source_endpoint_id)
      })

    assert {:ok, _spacecraft} = Cadence.persist_spacecraft(organization_id, spacecraft)

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(organization_id, source_endpoint)

    assert {:ok, persisted_binding_set} =
             Cadence.persist_binding_set(organization_id, binding_set)

    assert {:ok, ^counter_limit} = Cadence.persist_limit_definition(counter_limit)
    assert {:ok, ^voltage_limit} = Cadence.persist_limit_definition(voltage_limit)

    assert {:ok, _scheduled_contact} =
             Cadence.persist_scheduled_contact(organization_id, scheduled_contact)

    assert {:ok, _canceled_contact} =
             Cadence.cancel_scheduled_contact(
               organization_id,
               mission_id,
               scheduled_contact.scheduled_contact_id,
               reason: "weather"
             )

    assert {:ok, _result} =
             Cadence.process_and_persist_telemetry_ingress(
               raw_evidence_fixture(mission_id, "sc-001", 30, 50, 1_700_090_100),
               persisted_binding_set.binding_set_id,
               persisted_binding_set.version
             )

    assert {:ok, limit_run} = Cadence.evaluate_telemetry_limits(organization_id, mission_id, [])
    assert limit_run.status == :completed
  end

  defp contact_paths(source_endpoint_ref) do
    [
      Path.new(%{
        path_id: "uplink-path-read-models",
        direction: :uplink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      }),
      Path.new(%{
        path_id: "downlink-path-read-models",
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: source_endpoint_ref
      })
    ]
  end

  defp persist_active_uplink_contact_for_command_release(
         organization_id,
         mission_id,
         source_endpoint_ref
       ) do
    realized_contact =
      RealizedContact.new(%{
        realized_contact_id:
          "realized-contact-commanding-" <> Integer.to_string(System.unique_integer([:positive])),
        organization_id: organization_id,
        mission_id: mission_id,
        source_endpoint_refs: [source_endpoint_ref],
        clock_mode: :replay,
        initial_time: DateTime.from_unix!(1_700_410_000, :second),
        paths: [
          Path.new(%{
            path_id: "uplink-path-commanding-api",
            direction: :uplink,
            selection_role: :selected,
            source_endpoint_ref: source_endpoint_ref,
            transport_bindings: [
              TransportBinding.new(%{
                transport_binding_id: "uplink-gateway-commanding-api",
                family_key: :uplink_gateway,
                target_scope: :path,
                configuration: %{"service_name" => "gateway"}
              })
            ]
          })
        ]
      })

    assert {:ok, _persisted_realized_contact} =
             Cadence.persist_realized_contact(organization_id, realized_contact)

    assert {:ok, _pid} =
             Cadence.start_realized_contact(
               organization_id,
               mission_id,
               realized_contact.realized_contact_id
             )

    realized_contact
  end

  defp raw_evidence_fixture(mission_id, source_ref, counter_value, voltage_value, receipt_unix) do
    RawEvidence.new(%{
      mission_id: mission_id,
      source_ref: source_ref,
      receipt_time: DateTime.from_unix!(receipt_unix, :second),
      raw: build_space_packet(42, 1, <<counter_value::16, voltage_value::16>>)
    })
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end

  defp build_tm_single_frame(apid, sequence_count, packet_data, frame_size) do
    packet = build_space_packet(apid, sequence_count, packet_data)

    sdu = %SDUOctets{
      profile: :tm,
      scid: 11,
      vcid: 2,
      map_id: nil,
      direction: :downlink,
      sdu_kind_hint: :space_packet,
      octets: packet,
      quality: :good,
      source_frames: [],
      timestamp: nil,
      meta: %{}
    }

    {:ok, segmentation_state} = Segmentation.init(vcfc: 0)

    {:ok, encoded_frames, _segmentation_state} =
      Segmentation.segment_encode(
        sdu,
        %{frame_size: frame_size, ocf_length: 0},
        segmentation_state,
        []
      )

    <<encoded_frame::binary-size(frame_size), _rest::binary>> = encoded_frames
    encoded_frame
  end
end
