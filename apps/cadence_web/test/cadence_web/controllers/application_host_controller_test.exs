defmodule CadenceWeb.ApplicationHostControllerTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission
  alias Cadence.Reads.ApplicationSurfaces.Comms, as: CommsSurface
  alias Cadence.Repo
  alias CadenceWeb.{ApplicationHostCatalog, TestFixtures}

  @catalog_suffix "/api/cadence/application-host/v1/missions"

  test "generic federation shells preserve literal URL selectors in the bounded host payload" do
    {conn, _org, mission, _scope} = signed_in_scope_and_mission()

    query = %{
      "dashboard_id" => "dashboard/a?+🌍",
      "version" => "9007199254740990",
      "selected_publish_issue" => "issue/\"<tag>&+"
    }

    html =
      conn
      |> get(
        "/missions/#{mission.mission_id}/applications/ops_console/dashboard_activity/federated?" <>
          URI.encode_query(query)
      )
      |> html_response(200)

    root = html |> LazyHTML.from_fragment() |> LazyHTML.query("#cadence-federation-root")
    assert [encoded] = LazyHTML.attribute(root, "data-query-params")
    assert Jason.decode!(encoded) == query
  end

  test "generic federation shells reject ambiguous or unbounded selectors without mounting a broader page" do
    {conn, _org, mission, _scope} = signed_in_scope_and_mission()

    path =
      "/missions/#{mission.mission_id}/applications/ops_console/dashboard_activity/federated?"

    for query <- [
          "dashboard_id=one&dashboard_id=two",
          "dashboard_id=one&dashboard%5Fid=two",
          "dashboard_id[]=one",
          "dashboard_id=" <> String.duplicate("x", 257),
          "__proto__=one",
          "dashboard_id=bad%0A",
          URI.encode_query(Map.new(1..65, &{"key#{&1}", "v"})),
          URI.encode_query(
            Map.new(
              1..64,
              &{String.duplicate("k", 240) <> to_string(&1), String.duplicate("v", 256)}
            )
          )
        ] do
      response = get(conn, path <> query)
      assert redirected_to(response) == "/missions"
      html = response.resp_body

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#cadence-federation-root")
             |> LazyHTML.attribute("id") == []
    end
  end

  test "the generic compatibility shell is protected and the Comms LiveView remains the fallback",
       %{
         conn: conn
       } do
    assert conn
           |> get("/missions/mission-missing/applications/comms_overview/federated")
           |> redirected_to() == "/sign-in"

    {member_conn, _organization, mission, _scope} = signed_in_scope_and_mission()

    federated_html =
      member_conn
      |> get("/missions/#{mission.mission_id}/applications/comms_overview/federated")
      |> html_response(200)

    assert federated_html =~ ~s(<div id="cadence-federation-root")
    assert federated_html =~ ~s(data-mission-id="#{mission.mission_id}")
    assert federated_html =~ ~s(data-application-key="comms_overview")
    assert federated_html =~ ~s(data-surface-id="overview")
    assert federated_html =~ ~s(data-fallback-href="/missions/#{mission.mission_id}/comms")
    refute federated_html =~ ~s(data-spacecraft-id=)

    expected_catalog_url =
      catalog_path(mission.mission_id) <>
        "?" <>
        URI.encode_query(%{"application_key" => "comms_overview", "surface_id" => "overview"})

    document = LazyHTML.from_fragment(federated_html)
    root = LazyHTML.query(document, "#cadence-federation-root")
    assert [^expected_catalog_url] = LazyHTML.attribute(root, "data-catalog-url")

    refute federated_html =~ ~s(src="/assets/application-host/host/host.js")

    refute federated_html =~ "plugin-host.css"
    assert federated_html =~ ~s(href="/assets/app.css")

    {:ok, view, _html} =
      live(member_conn, "/missions/#{mission.mission_id}/comms")

    assert has_element?(view, "#application-shell")
  end

  test "organization-scope host shells retain the authenticated browser gate", %{conn: conn} do
    assert conn
           |> get("/applications/organization_admin/organization_home/federated")
           |> redirected_to() == "/sign-in"
  end

  test "organization-scope catalog route builds a positive host context without a mission id" do
    {member_conn, organization, _mission, _scope} = signed_in_scope_and_mission()

    catalog =
      member_conn
      |> get(
        "/api/cadence/application-host/v1/catalog?scope=organization&organization_id=#{organization.organization_id}"
      )
      |> json_response(200)

    assert catalog["session"]["context"]["scope"] == "organization"
    assert catalog["session"]["context"]["organizationId"] == organization.organization_id
    assert catalog["session"]["context"]["missionId"] == nil
  end

  test "organization-scope root query admits an installation-exempt Mission Catalog surface" do
    {member_conn, organization, _mission, _scope} = signed_in_scope_and_mission()

    {catalog_conn, catalog} =
      member_conn
      |> get(
        "/api/cadence/application-host/v1/catalog?scope=organization&organization_id=#{organization.organization_id}"
      )
      |> then(fn conn -> {conn, json_response(conn, 200)} end)

    response =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json("/api/cadence/application-host/v1/query", %{
        "applicationKey" => "mission_catalog",
        "applicationVersion" => 1,
        "surfaceId" => "mission_list",
        "surfaceVersion" => 1,
        "queryId" => "cadence.mission_catalog.mission_list",
        "queryVersion" => 1,
        "params" => %{},
        "scope" => %{
          "scope" => "organization",
          "organizationId" => organization.organization_id
        }
      })

    assert %{"trusted_surface" => %{"presentation" => presentation}} =
             json_response(response, 200)

    assert presentation["header"]["title"]["text"] == "Missions"
  end

  test "catalog manifest URLs preserve the browser request origin" do
    {member_conn, organization, _mission, _scope} = signed_in_scope_and_mission()

    path =
      "/api/cadence/application-host/v1/catalog?" <>
        URI.encode_query(%{
          "application_key" => "mission_catalog",
          "surface_id" => "mission_list",
          "scope" => "organization",
          "organization_id" => organization.organization_id
        })

    for origin <- [
          "http://localhost:4001",
          "http://127.0.0.1:4001",
          "https://cadence.example:4443"
        ] do
      catalog = member_conn |> get(origin <> path) |> json_response(200)

      assert [%{"release" => %{"manifestUrl" => manifest_url}}] = catalog["applications"]
      assert manifest_url == origin <> "/assets/application-host/mission-catalog/mf-manifest.json"
    end
  end

  test "organization home catalog and query use the authenticated root surface contract" do
    {member_conn, organization, _mission, _scope} = signed_in_scope_and_mission()

    catalog_url =
      "/api/cadence/application-host/v1/catalog?" <>
        URI.encode_query(%{
          "application_key" => "organization_admin",
          "organization_id" => organization.organization_id,
          "scope" => "organization",
          "surface_id" => "organization_home"
        })

    {catalog_conn, catalog} =
      member_conn
      |> get(catalog_url)
      |> then(fn conn -> {conn, json_response(conn, 200)} end)

    assert [
             %{
               "applicationKey" => "organization_admin",
               "surface" => %{"surfaceId" => "organization_home"}
             }
           ] =
             catalog["applications"]

    response =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json("/api/cadence/application-host/v1/query", %{
        "applicationKey" => "organization_admin",
        "applicationVersion" => 1,
        "surfaceId" => "organization_home",
        "surfaceVersion" => 1,
        "queryId" => "cadence.organization.home",
        "queryVersion" => 1,
        "params" => %{},
        "scope" => %{
          "scope" => "organization",
          "organizationId" => organization.organization_id
        }
      })

    assert json_response(response, 200)["trusted_surface"] == %{
             "organization_id" => organization.organization_id
           }
  end

  test "organization members cannot query the privileged provider-account surface" do
    {member_conn, organization, _mission, _scope} = signed_in_scope_and_mission()

    catalog_url =
      "/api/cadence/application-host/v1/catalog?" <>
        URI.encode_query(%{
          "application_key" => "organization_admin",
          "organization_id" => organization.organization_id,
          "scope" => "organization",
          "surface_id" => "provider_accounts"
        })

    {catalog_conn, catalog} =
      member_conn
      |> get(catalog_url)
      |> then(fn conn -> {conn, json_response(conn, 200)} end)

    response =
      catalog_conn
      |> bridge_conn(catalog)
      |> post_json("/api/cadence/application-host/v1/query", %{
        "applicationKey" => "organization_admin",
        "applicationVersion" => 1,
        "surfaceId" => "provider_accounts",
        "surfaceVersion" => 1,
        "queryId" => "cadence.organization.provider_accounts.list",
        "queryVersion" => 1,
        "params" => %{},
        "scope" => %{
          "scope" => "organization",
          "organizationId" => organization.organization_id
        }
      })

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "forbidden"
           } = json_response(response, 403)
  end

  test "mission catalog accepts the browser context query on its scoped route" do
    {member_conn, _organization, mission, _scope} = signed_in_scope_and_mission()

    catalog =
      member_conn
      |> get(
        "/api/cadence/application-host/v1/missions/#{mission.mission_id}/catalog?scope=mission&mission_id=#{mission.mission_id}"
      )
      |> json_response(200)

    assert catalog["session"]["context"]["scope"] == "mission"
    assert catalog["session"]["context"]["missionId"] == mission.mission_id
  end

  test "legacy federated shells advertise and serve their exact filtered catalog surface" do
    {member_conn, _organization, mission, _scope} = signed_in_scope_and_mission()

    shell =
      member_conn
      |> get("/missions/#{mission.mission_id}/applications/comms_overview/federated")
      |> html_response(200)

    catalog_url =
      catalog_path(mission.mission_id) <>
        "?" <>
        URI.encode_query(%{"application_key" => "comms_overview", "surface_id" => "overview"})

    document = LazyHTML.from_fragment(shell)
    root = LazyHTML.query(document, "#cadence-federation-root")
    assert [^catalog_url] = LazyHTML.attribute(root, "data-catalog-url")

    catalog = member_conn |> get(catalog_url) |> json_response(200)

    assert [%{"applicationKey" => "comms_overview", "surface" => %{"surfaceId" => "overview"}}] =
             catalog["applications"]
  end

  test "organization federated shells retain scope ids with exact catalog filters" do
    {member_conn, organization, _mission, _scope} = signed_in_scope_and_mission()

    shell =
      member_conn
      |> get("/applications/organization_admin/organization_home/federated")
      |> html_response(200)

    expected_catalog_url =
      "/api/cadence/application-host/v1/catalog?" <>
        URI.encode_query(%{
          "application_key" => "organization_admin",
          "organization_id" => organization.organization_id,
          "scope" => "organization",
          "surface_id" => "organization_home"
        })

    document = LazyHTML.from_fragment(shell)
    root = LazyHTML.query(document, "#cadence-federation-root")
    assert [^expected_catalog_url] = LazyHTML.attribute(root, "data-catalog-url")
  end

  test "generic shell fallbacks target the existing mission and spacecraft LiveViews" do
    mission_context = %{host_context: HostContext.mission("mission-1")}
    spacecraft_context = %{host_context: HostContext.spacecraft("mission-1", "spacecraft-1")}

    assert {:ok, "/missions/mission-1/applications/derived_telemetry"} ==
             ApplicationHostCatalog.fallback_href(mission_context, "derived_telemetry", nil)

    assert {:ok,
            "/missions/mission-1/spacecraft/spacecraft-1/applications/telemetry_decom/packet_bindings"} ==
             ApplicationHostCatalog.fallback_href(
               spacecraft_context,
               "telemetry_decom",
               "packet_bindings"
             )
  end

  test "the browser-session catalog advertises platform modules without installations", %{
    conn: _conn
  } do
    {member_conn, organization, mission, _scope} = signed_in_scope_and_mission()
    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)

    assert catalog["schema"] == "cadence.first-party-frontend-catalog.v1"
    assert catalog["hostContract"] == "cadence.application-host.v1"
    assert is_binary(catalog["generatedAt"])

    assert Enum.sort(Enum.map(catalog["applications"], & &1["applicationKey"])) ==
             ["comms", "comms_overview", "mission_catalog", "ops_console", "spacecraft"]

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

    assert application =
             Enum.find(catalog["applications"], &(&1["applicationKey"] == "comms_overview"))

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
             "renderer" => %{
               "kind" => "federated-vue",
               "exposedModule" => "./LegacyApplication"
             }
           }

    release = application["release"]
    assert release["federation"] == "module_federation"
    assert release["remoteName"] == "cadence_comms"
    assert release["exposedModule"] == "./LegacyApplication"
    assert release["manifestUrl"] =~ ~r{\Ahttps?://}

    assert String.ends_with?(
             release["manifestUrl"],
             "/assets/application-host/comms/mf-manifest.json"
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
        "applicationKey" => "comms_overview",
        "applicationVersion" => 1,
        "surfaceId" => "overview",
        "surfaceVersion" => 1,
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
        "applicationKey" => "comms_overview",
        "applicationVersion" => 1,
        "surfaceId" => "overview",
        "surfaceVersion" => 1,
        "queryId" => "cadence.comms.overview",
        "version" => 1,
        "scope" => valid_scope,
        "actor" => %{"displayName" => "Ignored actor", "permissions" => ["admin"]}
      })

    assert {:ok, presentation} = CommsSurface.overview_presentation(scope, mission)

    response = json_response(query_response, 200)

    assert response == %{
             "queryVersion" => 1,
             "presentation" => Jason.decode!(Jason.encode!(presentation))
           }

    assert Jason.decode!(Jason.encode!(presentation)) == response["presentation"]
  end

  test "scoped Comms queries preserve the core read contract and identity", %{conn: _conn} do
    {member_conn, organization, mission, scope} = signed_in_scope_and_mission()
    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)
    valid_scope = scope_document(organization, mission)

    response =
      post_bridge(catalog, catalog_conn, mission.mission_id, %{
        "applicationKey" => "comms_overview",
        "applicationVersion" => 1,
        "surfaceId" => "overview",
        "surfaceVersion" => 1,
        "queryId" => "cadence.comms.overview",
        "queryVersion" => 1,
        "scope" => valid_scope
      })

    assert {:ok, presentation} = CommsSurface.overview_presentation(scope, mission)

    assert json_response(response, 200) == %{
             "queryVersion" => 1,
             "presentation" => Jason.decode!(Jason.encode!(presentation))
           }

    rejected =
      post_bridge(catalog, catalog_conn, mission.mission_id, %{
        "applicationKey" => "comms_overview",
        "applicationVersion" => 1,
        "surfaceId" => "wrong_surface",
        "surfaceVersion" => 1,
        "queryId" => "cadence.comms.overview",
        "queryVersion" => 1,
        "scope" => valid_scope
      })

    assert %{"code" => "unsupported_query"} = json_response(rejected, 404)
  end

  test "an installed first-class Comms application is present with its canonical release" do
    {member_conn, _organization, mission, scope} = signed_in_scope_and_mission()
    host_context = HostContext.mission(mission.mission_id)

    assert {:error, :platform_application} =
             ApplicationInstallations.install(scope, host_context, "comms")

    {_catalog_conn, catalog} = fetch_catalog(member_conn, mission)

    assert application = Enum.find(catalog["applications"], &(&1["applicationKey"] == "comms"))
    assert application["package"] == %{"packageId" => "cadence.comms", "version" => 1}
    assert application["release"]["remoteName"] == "cadence_comms"
    assert application["release"]["exposedModule"] == "./Application"

    assert application["release"]["manifestUrl"] =~
             "/assets/application-host/comms/mf-manifest.json"
  end

  test "canonical Comms query emits the un-nested trusted surface envelope" do
    {member_conn, organization, mission, scope} = signed_in_scope_and_mission()
    host_context = HostContext.mission(mission.mission_id)

    assert {:error, :platform_application} =
             ApplicationInstallations.install(scope, host_context, "comms")

    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)
    valid_scope = scope_document(organization, mission)

    response =
      post_bridge(catalog, catalog_conn, mission.mission_id, %{
        "applicationKey" => "comms",
        "applicationVersion" => 1,
        "surfaceId" => "overview",
        "surfaceVersion" => 1,
        "queryId" => "cadence.comms.overview",
        "queryVersion" => 1,
        "scope" => valid_scope
      })

    expected_fallback_href = "/missions/#{mission.mission_id}/comms"

    assert %{
             "navigation" => %{"fallback_href" => ^expected_fallback_href},
             "trusted_surface" => trusted_surface
           } = json_response(response, 200)

    assert trusted_surface["root"]["attrs"]["id"] == "comms-overview-page"
    assert trusted_surface["overview"]["transport"]["id"] == "comms-transports"
    refute Map.has_key?(trusted_surface, "data")
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
          %{
            "applicationKey" => "comms_overview",
            "applicationVersion" => 1,
            "surfaceId" => "overview",
            "surfaceVersion" => 1,
            "queryId" => "cadence.comms.unknown",
            "version" => 1
          },
          %{
            "applicationKey" => "comms_overview",
            "applicationVersion" => 1,
            "surfaceId" => "overview",
            "surfaceVersion" => 1,
            "queryId" => "cadence.comms.overview",
            "version" => 2
          }
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
          "surfaceId" => "overview",
          "surfaceVersion" => 1,
          "actionId" => "anything",
          "params" => %{},
          "scope" => valid_scope
        },
        :actions
      )

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "unsupported_action"
           } = json_response(action_response, 404)
  end

  test "unauthenticated application-host requests use the browser gate", %{conn: conn} do
    response = get(conn, catalog_path("mission-missing"))

    assert redirected_to(response) == "/sign-in"
  end

  test "authenticated host routes negotiate JSON inside the browser pipeline" do
    {member_conn, _organization, mission, _scope} = signed_in_scope_and_mission()

    response =
      member_conn
      |> put_req_header("accept", "application/json")
      |> get(catalog_path(mission.mission_id))

    assert response.status == 200
    assert is_map(json_response(response, 200))
  end

  test "post-cutover missing-generation catalog failure is a sanitized service-unavailable response" do
    {member_conn, organization, mission, _scope} = signed_in_scope_and_mission()
    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)
    valid_scope = scope_document(organization, mission)

    assert [[1]] =
             Repo.query!("""
             UPDATE frontend_release_activation_controls
             SET cutover_epoch = 1, cutover_at = now()
             WHERE control_id = 1
             RETURNING cutover_epoch
             """).rows

    catalog_response = get(member_conn, catalog_path(mission.mission_id))

    query_response =
      post_bridge(catalog, catalog_conn, mission.mission_id, %{
        "applicationKey" => "comms_overview",
        "applicationVersion" => 1,
        "surfaceId" => "overview",
        "surfaceVersion" => 1,
        "queryId" => "cadence.comms.overview",
        "version" => 1,
        "scope" => valid_scope
      })

    action_response =
      post_bridge(
        catalog,
        catalog_conn,
        mission.mission_id,
        %{
          "applicationKey" => "comms_overview",
          "applicationVersion" => 1,
          "surfaceId" => "overview",
          "surfaceVersion" => 1,
          "actionId" => "anything",
          "params" => %{},
          "scope" => valid_scope
        },
        :actions
      )

    for response <- [catalog_response, query_response, action_response] do
      assert %{
               "schema" => "cadence.application-host-problem.v1",
               "code" => "application_catalog_unavailable",
               "message" => "The application catalog is temporarily unavailable."
             } = json_response(response, 503)

      assert get_resp_header(response, "cache-control") == ["no-store"]
      refute response.resp_body =~ "integrity_failure"
      refute response.resp_body =~ "active_generation_missing"
    end
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

    conn = bridge_conn(conn, catalog)

    conn =
      if endpoint == :actions do
        put_req_header(conn, "idempotency-key", "legacy-action-test")
      else
        conn
      end

    post_json(conn, path, body)
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
