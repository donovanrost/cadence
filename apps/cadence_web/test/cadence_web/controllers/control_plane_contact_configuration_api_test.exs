defmodule CadenceWeb.ControlPlaneContactConfigurationApiTest do
  use CadenceWeb.ConnCase, async: true

  import CadenceWeb.ControlPlaneApiFixtures

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
end
