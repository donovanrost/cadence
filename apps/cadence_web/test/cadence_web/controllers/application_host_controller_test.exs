defmodule CadenceWeb.ApplicationHostControllerTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission
  alias CadenceWeb.{CommsOverviewPresenter, TestFixtures}

  @catalog_suffix "/api/cadence/application-host/v1/missions"

  test "the opt-in shell is protected and the existing Comms route remains the fallback", %{
    conn: conn
  } do
    assert conn
           |> get("/missions/mission-missing/comms/federated")
           |> redirected_to() == "/sign-in"

    {member_conn, _organization, mission, _scope} = signed_in_scope_and_mission()

    federated_html =
      member_conn
      |> get("/missions/#{mission.mission_id}/comms/federated")
      |> html_response(200)

    assert federated_html =~ ~s(<div id="cadence-federation-root")
    assert federated_html =~ ~s(data-mission-id="#{mission.mission_id}")

    assert federated_html =~
             ~s(data-catalog-url="#{catalog_path(mission.mission_id)}")

    assert federated_html =~
             ~s(<script type="module" src="/assets/application-host/host/host.js">)

    assert federated_html =~
             ~s(<link rel="stylesheet" href="/assets/application-host/host/plugin-host.css">)

    assert federated_html =~ ~s(href="/assets/app.css")

    {:ok, view, _html} =
      live(member_conn, "/missions/#{mission.mission_id}/comms")

    assert has_element?(view, "#comms-overview-component")
  end

  test "the browser-session catalog is server-owned and advertises only Comms overview", %{
    conn: _conn
  } do
    {member_conn, organization, mission, _scope} = signed_in_scope_and_mission()
    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)

    assert catalog["schema"] == "cadence.first-party-frontend-catalog.v1"
    assert catalog["hostContract"] == "cadence.application-host.v1"
    assert is_binary(catalog["generatedAt"])
    assert catalog["applications"] |> length() == 1

    session = catalog["session"]
    assert is_binary(session["sessionId"])
    assert is_binary(session["csrfToken"])
    assert session["bridgeBaseUrl"] == bridge_path(mission.mission_id)

    context = session["context"]

    assert context == %{
             "organizationId" => organization.organization_id,
             "missionId" => mission.mission_id,
             "missionName" => mission.display_name,
             "scope" => "mission",
             "spacecraftId" => nil,
             "spacecraftName" => nil,
             "actor" => %{
               "displayName" => "Durable User",
               "permissions" => ["applications:view"]
             }
           }

    assert [application] = catalog["applications"]
    assert application["applicationKey"] == "comms_overview"
    assert application["applicationVersion"] == 1
    assert application["package"] == %{"packageId" => "cadence.comms_overview", "version" => 1}

    assert application["surface"] == %{
             "surfaceId" => "overview",
             "version" => 1,
             "purpose" => "overview",
             "scope" => "mission",
             "placement" => "application_workspace",
             "navigation" => %{"label" => "Overview", "order" => 10},
             "dataContract" => %{"id" => "cadence.comms.overview", "version" => 1},
             "actions" => [],
             "renderer" => %{"kind" => "federated-vue", "exposedModule" => "./Application"}
           }

    release = application["release"]
    assert release["federation"] == "module_federation"
    assert release["remoteName"] == "cadence_comms_overview"
    assert release["exposedModule"] == "./Application"
    assert release["manifestUrl"] =~ ~r{\Ahttps?://}

    assert String.ends_with?(
             release["manifestUrl"],
             "/assets/application-host/comms-overview/mf-manifest.json"
           )

    refute Jason.encode!(catalog) =~ "user_session_token"
    assert get_resp_header(catalog_conn, "cache-control") == ["no-store"]
  end

  test "catalog and typed query are isolated to the current organization and route scope", %{
    conn: _conn
  } do
    {member_conn, organization, mission, scope} = signed_in_scope_and_mission()
    other_organization = TestFixtures.persist_org!(display_name: "Other Organization")
    other_mission = TestFixtures.persist_mission!(other_organization)

    assert %{"code" => "mission_not_found"} =
             member_conn
             |> get(catalog_path(other_mission.mission_id))
             |> json_response(404)

    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)

    forged_scope = %{
      "organizationId" => other_organization.organization_id,
      "missionId" => other_mission.mission_id,
      "spacecraftId" => nil
    }

    response =
      post_bridge(catalog, catalog_conn, mission.mission_id, %{
        "queryId" => "cadence.comms.overview",
        "version" => 1,
        "scope" => forged_scope,
        "actor" => %{"displayName" => "Forged actor", "permissions" => ["admin"]}
      })

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "invalid_scope",
             "message" => "The requested application scope is invalid."
           } = json_response(response, 400)

    same_organization_mission = TestFixtures.persist_mission!(organization)

    assert %{"code" => "invalid_scope"} =
             post_bridge(catalog, catalog_conn, same_organization_mission.mission_id, %{
               "queryId" => "cadence.comms.overview",
               "version" => 1,
               "scope" => scope_document(organization, same_organization_mission)
             })
             |> json_response(400)

    valid_scope = scope_document(organization, mission)

    query_response =
      post_bridge(catalog, catalog_conn, mission.mission_id, %{
        "queryId" => "cadence.comms.overview",
        "version" => 1,
        "scope" => valid_scope,
        "actor" => %{"displayName" => "Ignored actor", "permissions" => ["admin"]}
      })

    presentation = CommsOverviewPresenter.build(scope, mission)

    response = json_response(query_response, 200)

    assert response == %{
             "queryVersion" => 1,
             "presentation" => Jason.decode!(Jason.encode!(presentation))
           }

    assert Jason.decode!(Jason.encode!(presentation)) == response["presentation"]
  end

  test "JSON bridge requests require the catalog CSRF token and opaque host session", %{
    conn: _conn
  } do
    {member_conn, organization, mission, _scope} = signed_in_scope_and_mission()
    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)
    valid_scope = scope_document(organization, mission)

    missing_csrf =
      catalog_conn
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-cadence-poc-session", catalog["session"]["sessionId"])
      |> post_json(
        query_path(mission.mission_id),
        %{
          "queryId" => "cadence.comms.overview",
          "version" => 1,
          "scope" => valid_scope
        },
        csrf: nil
      )

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "invalid_csrf",
             "message" => "The request CSRF token is invalid."
           } = json_response(missing_csrf, 403)

    invalid_session =
      catalog_conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-cadence-poc-session", "forged-session")
      |> put_req_header("x-csrf-token", catalog["session"]["csrfToken"])
      |> post_json(query_path(mission.mission_id), %{
        "queryId" => "cadence.comms.overview",
        "version" => 1,
        "scope" => valid_scope
      })

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "invalid_session"
           } = json_response(invalid_session, 401)
  end

  test "unknown query versions, invalid scopes, and all actions return host problems", %{
    conn: _conn
  } do
    {member_conn, organization, mission, _scope} = signed_in_scope_and_mission()
    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)
    valid_scope = scope_document(organization, mission)

    for request <- [
          %{"queryId" => "cadence.comms.unknown", "version" => 1},
          %{"queryId" => "cadence.comms.overview", "version" => 2}
        ] do
      response =
        post_bridge(
          catalog,
          catalog_conn,
          mission.mission_id,
          Map.put(request, "scope", valid_scope)
        )

      assert %{
               "schema" => "cadence.application-host-problem.v1",
               "code" => "unsupported_query"
             } = json_response(response, 404)
    end

    invalid_scope_response =
      post_bridge(catalog, catalog_conn, mission.mission_id, %{
        "queryId" => "cadence.comms.overview",
        "version" => 1,
        "scope" => %{"organizationId" => organization.organization_id}
      })

    assert %{"code" => "invalid_scope"} = json_response(invalid_scope_response, 400)

    action_response =
      post_bridge(
        catalog,
        catalog_conn,
        mission.mission_id,
        %{
          "applicationKey" => "comms_overview",
          "applicationVersion" => 1,
          "actionId" => "anything",
          "input" => %{},
          "scope" => valid_scope
        },
        :actions
      )

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "unsupported_action"
           } = json_response(action_response, 404)
  end

  test "unauthenticated catalog requests receive a JSON 401", %{conn: conn} do
    response = get(conn, catalog_path("mission-missing"))

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "unauthenticated"
           } = json_response(response, 401)
  end

  defp signed_in_scope_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization, display_name: "Primary Mission")

    scope =
      Scope.new(%{
        user: user,
        organization_id: organization.organization_id,
        organization: organization,
        organization_membership: membership
      })

    {TestFixtures.member_conn(user), organization, mission, scope}
  end

  defp fetch_catalog(conn, %Mission{mission_id: mission_id}) do
    catalog_conn = get(conn, catalog_path(mission_id))
    {catalog_conn, json_response(catalog_conn, 200)}
  end

  defp catalog_path(mission_id), do: @catalog_suffix <> "/" <> mission_id <> "/catalog"

  defp query_path(mission_id), do: @catalog_suffix <> "/" <> mission_id <> "/query"

  defp bridge_path(mission_id), do: "/api/cadence/application-host/v1/missions/#{mission_id}"

  defp scope_document(organization, mission) do
    %{
      "organizationId" => organization.organization_id,
      "missionId" => mission.mission_id,
      "spacecraftId" => nil
    }
  end

  defp post_bridge(catalog, conn, mission_id, body, endpoint \\ :query) do
    path =
      case endpoint do
        :query -> query_path(mission_id)
        :actions -> @catalog_suffix <> "/#{mission_id}/actions"
      end

    conn
    |> bridge_conn(catalog)
    |> post_json(path, body)
  end

  defp bridge_conn(conn, catalog) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-cadence-poc-session", catalog["session"]["sessionId"])
    |> put_req_header("x-csrf-token", catalog["session"]["csrfToken"])
  end

  defp post_json(conn, path, body, opts \\ []) do
    conn =
      case Keyword.get(opts, :csrf, :present) do
        nil -> delete_req_header(conn, "x-csrf-token")
        _present -> conn
      end

    post(conn, path, Jason.encode!(body))
  end
end
