defmodule CadenceWeb.ControlPlaneMissionDataApiTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :runtime

  import CadenceWeb.ControlPlaneApiFixtures

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Jobs
  alias Cadence.Jobs.Runner, as: JobRunner
  alias Cadence.Runtime.MissionModelPlanDecoder

  defp assert_dev_telemetry_ingress(
         conn,
         api_token,
         organization_id,
         mission_id,
         binding_set_id,
         binding_set_version
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
                   "binding_set_version" => ^binding_set_version,
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
                   "binding_set_version" => ^binding_set_version,
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
      mission_model_revision_id: mission_model_revision_id,
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
            "mission_model_revision_id" => mission_model_revision_id,
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
          "mission_model_revision_id" => mission_model_revision_id,
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

  test "authenticated mission API activates an imported Mission Model and ingests dev space packets",
       %{
         conn: conn
       } do
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

    assert {:ok, _completed_job} = JobRunner.run_job(claimed_job.job_id)

    import_run_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs/#{import_run_id}"
      )

    assert %{
             "data" => %{
               "result_document" =>
                 %{
                   "mission_model" => %{"revision_id" => mission_model_revision_id}
                 } = result_document
             }
           } = json_response(import_run_show_conn, 200)

    assert {:ok, plans} =
             Cadence.MissionModels.fetch_runtime_plans(
               organization_id,
               mission_id,
               mission_model_revision_id
             )

    assert {:ok, [packet_definition]} =
             MissionModelPlanDecoder.telemetry_packet_definitions(plans)

    assert packet_definition.packet_name == "THERM"
    assert packet_definition.apid == 42

    binding_set_id = "mission-model-import:" <> import_run_id
    binding_set_version = 1
    capability_instance_id = "telemetry:" <> packet_definition.packet_definition_id

    binding_set =
      BindingSet.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        binding_set_id: binding_set_id,
        version: binding_set_version,
        capability_instances: [
          CapabilityInstance.new(%{
            capability_instance_id: capability_instance_id,
            family_key: :definition_bound_telemetry,
            target_scope: :mission,
            runtime_configuration: packet_definition
          })
        ],
        rules: [
          BindingRule.new(%{
            binding_rule_id: "route:" <> packet_definition.packet_definition_id,
            capability_instance_id: capability_instance_id,
            selector: %{
              scope: %{target_scope: :mission},
              match: %{packet_kind: :space_packet, apid: packet_definition.apid}
            },
            priority: 100,
            fanout_mode: :exclusive
          })
        ]
      })

    activated_model =
      Cadence.MissionModelFixtures.activate_imported_model!(
        organization_id,
        mission_id,
        result_document,
        binding_set: binding_set,
        reconcile?: true
      )

    assert activated_model.revision_id == mission_model_revision_id

    assert_dev_telemetry_ingress(
      conn,
      api_token,
      organization_id,
      mission_id,
      binding_set_id,
      binding_set_version
    )
  end

  test "authenticated mission API manages command stages, requests, approvals, and queue entries",
       %{conn: conn} do
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

    assert {:ok, _completed_job} = JobRunner.run_job(claimed_job.job_id)

    import_run_show_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/catalog_import_runs/#{import_run_id}"
      )

    assert %{
             "data" => %{
               "result_document" =>
                 %{
                   "mission_model" => %{"revision_id" => mission_model_revision_id}
                 } = result_document
             }
           } = json_response(import_run_show_conn, 200)

    assert {:ok, runtime_plans} =
             Cadence.MissionModels.fetch_runtime_plans(
               organization_id,
               mission_id,
               mission_model_revision_id
             )

    command_model =
      Cadence.MissionModelFixtures.activate_imported_model!(
        organization_id,
        mission_id,
        result_document
      )

    assert command_model.revision_id == mission_model_revision_id

    noop_command_id = fetch_command_id(runtime_plans, "NOOP")
    set_mode_command_id = fetch_command_id(runtime_plans, "SET_MODE")

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
        mission_model_revision_id: mission_model_revision_id,
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
