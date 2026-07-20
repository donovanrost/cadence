defmodule CadenceWeb.ControlPlaneMissionDataApiTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :config

  @bootstrap_admin_email "bootstrap-admin@example.com"
  @bootstrap_admin_password "bootstrap-password-123"

  import CadenceWeb.ControlPlaneApiFixtures

  alias Cadence.Jobs

  setup do
    previous_importers = Application.get_env(:cadence_catalog, :catalog_importers, [])
    previous_bootstrap_admin = Application.get_env(:cadence, :bootstrap_admin, [])

    Application.put_env(:cadence_catalog, :catalog_importers, [
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
      Application.put_env(:cadence_catalog, :catalog_importers, previous_importers)
      Application.put_env(:cadence, :bootstrap_admin, previous_bootstrap_admin)
    end)

    :ok
  end

  defp assert_dev_telemetry_ingress(
         conn,
         api_token,
         organization_id,
         mission_id,
         binding_set_id
       ) do
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

  defp assert_command_stage_queue_workflow(context) do
    %{
      conn: conn,
      api_token: api_token,
      organization_id: organization_id,
      mission_id: mission_id,
      command_snapshot_id: command_snapshot_id,
      noop_command_id: noop_command_id,
      set_mode_command_id: set_mode_command_id
    } = context

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

    %{
      noop_queue_entry_id: noop_queue_entry_id,
      staged_command_request_id: staged_command_request_id,
      staged_queue_entry_id: staged_queue_entry_id
    }
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
                 },
                 %{
                   "code" => "telemetry_compiler.apid_required",
                   "severity" => "error"
                 },
                 %{
                   "code" => "telemetry_compiler.apid_required",
                   "severity" => "error"
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
    Application.put_env(:cadence_catalog, :catalog_importers, [
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

    assert_dev_telemetry_ingress(
      conn,
      api_token,
      organization_id,
      mission_id,
      binding_set_id
    )
  end

  test "authenticated mission API manages command stages, requests, approvals, and queue entries",
       %{conn: conn} do
    Application.put_env(:cadence_catalog, :catalog_importers, [
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
             Cadence.Catalog.fetch_command_snapshot(
               organization_id,
               mission_id,
               command_snapshot_id
             )

    noop_command_id = fetch_command_id(command_snapshot, "NOOP")
    set_mode_command_id = fetch_command_id(command_snapshot, "SET_MODE")

    %{
      noop_queue_entry_id: noop_queue_entry_id,
      staged_command_request_id: staged_command_request_id,
      staged_queue_entry_id: staged_queue_entry_id
    } =
      assert_command_stage_queue_workflow(%{
        conn: conn,
        api_token: api_token,
        organization_id: organization_id,
        mission_id: mission_id,
        command_snapshot_id: command_snapshot_id,
        noop_command_id: noop_command_id,
        set_mode_command_id: set_mode_command_id
      })

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
end
