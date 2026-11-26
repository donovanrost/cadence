defmodule CadenceWeb.ControlPlaneApiTest do
  use CadenceWeb.ConnCase, async: false

  @moduletag :runtime

  import CadenceWeb.ControlPlaneApiFixtures

  test "retired contact and link APIs have no routes" do
    base = "/api/organizations/org/missions/mission"

    for {method, path} <- [
          {"GET", "/scheduled_contacts"},
          {"POST", "/scheduled_contacts/contact/realize"},
          {"GET", "/realized_contacts"},
          {"GET", "/realized_contacts/contact/runtime"},
          {"GET", "/realized_contacts/contact/paths/path/runtime"},
          {"POST", "/realized_contacts/contact/end_early"},
          {"GET", "/contact_actions"},
          {"GET", "/provider_profiles"},
          {"GET", "/transport_profiles"},
          {"GET", "/path_templates"},
          {"GET", "/link_assignments"}
        ] do
      assert :error ==
               Phoenix.Router.route_info(CadenceWeb.Router, method, base <> path, "localhost")
    end

    assert :error ==
             Phoenix.Router.route_info(
               CadenceWeb.Router,
               "GET",
               "/api/cadence/contact-workspace/v1/missions/mission/schedule",
               "localhost"
             )

    assert :error ==
             Phoenix.Router.route_info(
               CadenceWeb.Router,
               "GET",
               "/missions/mission/ops/contact-workspace",
               "localhost"
             )
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

    mission_model_revision =
      compile_and_approve_empty_mission_model!(organization_id, mission_id)

    activation_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/activations", %{
        "activation" => %{
          "mission_model_revision_id" => mission_model_revision.revision_id,
          "binding_set_id" => "ops",
          "version" => 1,
          "metadata" => %{"reason" => "bootstrap"}
        }
      })

    assert %{
             "data" => %{
               "request" => %{
                 "activation_request_id" => activation_request_id,
                 "organization_id" => ^organization_id,
                 "mission_id" => ^mission_id,
                 "binding_set_id" => "ops",
                 "binding_set_version" => 1,
                 "state" => "approval_pending"
               },
               "execution" => nil
             }
           } = json_response(activation_conn, 202)

    request_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/activation_requests/#{activation_request_id}"
      )

    assert %{
             "data" => %{
               "request" => %{"state" => "approval_pending"},
               "execution" => nil
             }
           } = json_response(request_conn, 200)

    service_approval_conn =
      conn
      |> authorize(api_token)
      |> post(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/activation_requests/#{activation_request_id}/approve",
        %{"decision" => %{"reason" => "services cannot provide the human approval"}}
      )

    assert %{"errors" => [%{"reason" => "human_activation_approver_required"}]} =
             json_response(service_approval_conn, 422)

    admin_scope = organization_admin_scope(organization_id)

    assert {:ok, approved_request, decision, approved_activation} =
             Cadence.Management.Activations.approve(
               admin_scope,
               activation_request_id,
               "approved by a browser-authenticated organization administrator"
             )

    assert approved_request.state == :approved
    assert decision.decision == :approved
    assert {:ok, execution} = Cadence.Control.Activations.execute(approved_activation)
    assert execution.status == :succeeded

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

  test "org-scoped control-plane token reaches a mission's resources", %{conn: conn} do
    %{conn: conn, api_token: api_token, organization_id: organization_id} = bootstrap(conn)

    # The REST mission create is retired (#384); the mission is made through the domain.
    mission_id = "mission-bravo"
    persist_mission!(organization_id, mission_id)

    persist_api_spacecraft!(organization_id, mission_id, %{
      spacecraft_id: "spacecraft-001",
      display_name: "SC-001"
    })

    # The REST create is retired (#328); the show read still answers in this mission's scope.
    spacecraft_conn =
      conn
      |> authorize(api_token)
      |> get(
        "/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft/spacecraft-001"
      )

    assert %{
             "data" => %{
               "spacecraft_id" => "spacecraft-001",
               "organization_id" => ^organization_id,
               "mission_id" => ^mission_id
             }
           } = json_response(spacecraft_conn, 200)

    # #328: the REST create is gone. A POST answers 404 and persists nothing.
    removed_conn =
      conn
      |> authorize(api_token)
      |> post("/api/organizations/#{organization_id}/missions/#{mission_id}/spacecraft", %{
        "spacecraft" => %{"spacecraft_id" => "spacecraft-002", "display_name" => "SC-002"}
      })

    assert removed_conn.status == 404

    assert {:error, :spacecraft_not_found} =
             Cadence.SpacecraftStore.fetch_spacecraft(mission_id, "spacecraft-002")

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

    assert_binding_set_activation(conn, api_token, organization_id, mission_id)
  end
end
