defmodule CadenceWeb.ControlPlaneMissionDataApiTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :runtime

  import CadenceWeb.ControlPlaneApiFixtures

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet, CapabilityInstance}
  alias Cadence.Auth.ServiceIdentity
  alias Cadence.Jobs
  alias Cadence.Jobs.Runner, as: JobRunner
  alias Cadence.Organizations.Organization
  alias Cadence.Runtime.MissionModelPlanDecoder
  alias CadenceWeb.TestFixtures

  # The dev ingest routes (a person's session, console API; #780) push one packet and one frame
  # through the real ingest path against an activated imported Mission Model, and the decoded
  # values are read back through the console API.
  defp assert_dev_telemetry_ingress(
         organization_id,
         mission_id,
         binding_set_id,
         binding_set_version
       ) do
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, %Organization{organization_id: organization_id})

    packet_hex =
      build_space_packet(42, 3, <<12.5::float-32, 1::size(1), 0::size(7)>>)
      |> Base.encode16(case: :lower)

    dev_ingress_conn =
      user
      |> TestFixtures.member_conn()
      |> post("/api/v1/missions/#{mission_id}/dev/space_packets", %{
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
      user
      |> TestFixtures.member_conn()
      |> post("/api/v1/missions/#{mission_id}/dev/tm_frames", %{
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

    assert_console_reads(organization_id, mission_id)
  end

  # #748: the catalog goes in through the one API (/api/v1) as a mission-pinned service, an
  # opted-in action; the run's result document is read back from the domain, as the console read omits it.
  defp import_catalog!(conn, organization_id, mission_id, file_name, yaml) do
    # /api/v1 admits a mission-pinned service only; the bootstrap identity spans the organization.
    {:ok, %{api_token: api_token}} =
      Cadence.Auth.issue_service_identity(
        ServiceIdentity.new(%{
          service_identity_id: "svc-catalog-import-#{System.unique_integer([:positive])}",
          organization_id: organization_id,
          mission_id: mission_id,
          display_name: "Catalog import pipeline",
          capabilities: [:mission_admin]
        }),
        %Cadence.Auth.Scope{
          actor_kind: :user,
          organization_id: organization_id,
          user: %Cadence.Accounts.User{user_id: "user-service-issuer"}
        }
      )

    path = Path.join(System.tmp_dir!(), "#{System.unique_integer([:positive])}-#{file_name}")
    File.write!(path, yaml)
    on_exit(fn -> File.rm(path) end)

    import_conn =
      conn
      |> authorize(api_token)
      |> post("/api/v1/missions/#{mission_id}/catalog/imports", %{
        "name" => "API catalog",
        "file" => %Plug.Upload{path: path, filename: file_name, content_type: "application/yaml"}
      })

    assert %{"data" => %{"import_run_id" => import_run_id}} = json_response(import_conn, 202)
    assert [claimed_job] = Jobs.claim_jobs(1)
    assert {:ok, _completed_job} = JobRunner.run_job(claimed_job.job_id)

    assert {:ok, %{result_document: result_document}} =
             Cadence.Catalog.fetch_import_run(organization_id, mission_id, import_run_id)

    {import_run_id, result_document}
  end

  defp assert_console_reads(organization_id, mission_id) do
    org = %Organization{organization_id: organization_id}
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)

    from = DateTime.utc_now() |> DateTime.add(-3_600) |> DateTime.to_iso8601()
    to = DateTime.utc_now() |> DateTime.add(3_600) |> DateTime.to_iso8601()

    history_path =
      "/api/v1/missions/#{mission_id}/telemetry/points/THERM.temperature_c/history" <>
        "?from=#{URI.encode_www_form(from)}&to=#{URI.encode_www_form(to)}"

    # Both ingested samples (the packet and the frame) decode to 12.5.
    assert %{"data" => %{"point_id" => "THERM.temperature_c", "buckets" => buckets}} =
             user |> TestFixtures.member_conn() |> get(history_path) |> json_response(200)

    assert buckets |> Enum.map(& &1["count"]) |> Enum.sum() == 2
    assert Enum.all?(buckets, &(&1["min"] == 12.5 and &1["max"] == 12.5))
  end

  defp assert_command_stage_queue_workflow(context) do
    %{
      conn: conn,
      api_token: api_token,
      organization_id: organization_id,
      mission_id: mission_id,
      source_endpoint_id: source_endpoint_id,
      mission_model_revision_id: mission_model_revision_id,
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
            "source_endpoint_ref" => source_endpoint_id,
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

    # Requests exist only as members of a command group (DECISIONS #61/#62), so a stage's items
    # leave no request behind: the REST stage cannot be submitted.
    command_requests_conn =
      conn
      |> authorize(api_token)
      |> get("/api/organizations/#{organization_id}/missions/#{mission_id}/command_requests")

    assert %{"data" => []} = json_response(command_requests_conn, 200)
    :ok
  end

  test "authenticated mission API activates an imported Mission Model and ingests dev space packets",
       %{
         conn: conn
       } do
    %{conn: conn, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    yaml = """
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

    {import_run_id,
     %{"mission_model" => %{"revision_id" => mission_model_revision_id}} = result_document} =
      import_catalog!(conn, organization_id, mission_id, "mission-alpha-dev.yaml", yaml)

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
      organization_id,
      mission_id,
      binding_set_id,
      binding_set_version
    )
  end

  test "authenticated mission API manages command stages and their items",
       %{conn: conn} do
    %{conn: conn, api_token: api_token, organization_id: organization_id, mission_id: mission_id} =
      bootstrap(conn)

    persist_api_spacecraft!(organization_id, mission_id, %{
      spacecraft_id: "spacecraft-commanding-001",
      display_name: "SC-CMD-001",
      # The release guard (#38) matches the gateway's SCID to the target's.
      scid: 31
    })

    admin = TestFixtures.persist_user!()

    TestFixtures.grant_membership!(admin, %Organization{organization_id: organization_id},
      role: :organization_admin
    )

    source_endpoint_conn =
      admin
      |> TestFixtures.member_conn()
      |> post(
        "/api/v1/missions/#{mission_id}/spacecraft/spacecraft-commanding-001/source-endpoints",
        %{
          "source_endpoint" => %{
            "source_ref" => "sc-cmd-001",
            "display_name" => "SC Commanding Endpoint"
          }
        }
      )

    assert %{"data" => %{"source_endpoint_id" => source_endpoint_id}} =
             json_response(source_endpoint_conn, 201)

    yaml = """
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

    {_import_run_id,
     %{"mission_model" => %{"revision_id" => mission_model_revision_id}} = result_document} =
      import_catalog!(conn, organization_id, mission_id, "commanding-api.yaml", yaml)

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

    set_mode_command_id = fetch_command_id(runtime_plans, "SET_MODE")

    assert_command_stage_queue_workflow(%{
      conn: conn,
      api_token: api_token,
      organization_id: organization_id,
      mission_id: mission_id,
      source_endpoint_id: source_endpoint_id,
      mission_model_revision_id: mission_model_revision_id,
      set_mode_command_id: set_mode_command_id
    })
  end
end
