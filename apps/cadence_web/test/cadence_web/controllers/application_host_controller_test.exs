defmodule CadenceWeb.ApplicationHostControllerTest do
  @moduledoc """
  The mission application bridge (`query` and `actions`). The console's surface host mints the
  host session id, CSRF token and pinned scope; these tests bootstrap from it.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Missions.Mission
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures

  @bridge_suffix "/api/cadence/application-host/v1/missions"

  test "queries are isolated to the current organization and route scope" do
    {member_conn, organization, mission, _scope} = signed_in_scope_and_mission()
    other_organization = TestFixtures.persist_org!(display_name: "Other Organization")
    other_mission = TestFixtures.persist_mission!(other_organization)

    # Another organization's mission is refused by the policy before it is looked up, the same
    # way a nonexistent one is, so the 404 reveals nothing.
    assert %{"error" => %{"code" => _}} =
             member_conn
             |> get(host_path(other_mission.mission_id))
             |> json_response(404)

    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)

    forged_scope = %{
      "organizationId" => other_organization.organization_id,
      "missionId" => other_mission.mission_id,
      "spacecraftId" => nil
    }

    response =
      post_bridge(catalog, catalog_conn, mission.mission_id, %{
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
             catalog
             |> post_bridge(catalog_conn, same_organization_mission.mission_id, %{
               "scope" => scope_document(organization, same_organization_mission)
             })
             |> json_response(400)

    assert %{"host" => %{"surface_id" => "manage"}} =
             catalog
             |> post_bridge(catalog_conn, mission.mission_id, %{
               "scope" => scope_document(organization, mission),
               "actor" => %{"displayName" => "Ignored actor", "permissions" => ["admin"]}
             })
             |> json_response(200)
  end

  test "L19b: a session keeps every scope it loaded, so two surfaces stay open at once" do
    {member_conn, organization, mission, scope} = signed_in_scope_and_mission()
    second = TestFixtures.persist_mission!(organization, display_name: "Second Mission")
    never_loaded = TestFixtures.persist_mission!(organization, display_name: "Third Mission")

    install_limits(scope, second)

    {first_conn, _first_catalog} = fetch_catalog(member_conn, mission)
    {second_conn, catalog} = fetch_catalog(recycle(first_conn), second)

    query = fn target ->
      post_bridge(catalog, second_conn, target.mission_id, %{
        "scope" => scope_document(organization, target)
      })
    end

    # The first mission's surface still answers after the second's catalog loaded.
    assert %{"host" => %{"surface_id" => "manage"}} = json_response(query.(mission), 200)
    assert %{"host" => %{"surface_id" => "manage"}} = json_response(query.(second), 200)
    assert %{"code" => "invalid_scope"} = json_response(query.(never_loaded), 400)
  end

  test "JSON bridge requests require the catalog CSRF token and opaque host session" do
    {member_conn, organization, mission, _scope} = signed_in_scope_and_mission()
    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)
    valid_scope = scope_document(organization, mission)
    session = catalog["session"]

    missing_csrf =
      catalog_conn
      |> recycle()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-cadence-poc-session", session["sessionId"])
      |> post_json(query_path(mission.mission_id), %{"scope" => valid_scope}, csrf: nil)

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
      |> put_req_header("x-csrf-token", session["csrfToken"])
      |> post_json(query_path(mission.mission_id), %{"scope" => valid_scope})

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "invalid_session"
           } = json_response(invalid_session, 401)
  end

  test "unknown query versions, invalid scopes, and unknown actions return host problems" do
    {member_conn, organization, mission, _scope} = signed_in_scope_and_mission()
    {catalog_conn, catalog} = fetch_catalog(member_conn, mission)
    valid_scope = scope_document(organization, mission)

    for request <- [
          %{"queryId" => "cadence.limits.unknown", "queryVersion" => 1},
          %{"queryId" => "cadence.limits.manage", "queryVersion" => 2}
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
        "scope" => %{"organizationId" => organization.organization_id}
      })

    assert %{"code" => "invalid_scope"} = json_response(invalid_scope_response, 400)

    action_response =
      post_bridge(
        catalog,
        catalog_conn,
        mission.mission_id,
        %{"actionId" => "anything", "params" => %{}, "scope" => valid_scope},
        :actions
      )

    assert %{
             "schema" => "cadence.application-host-problem.v1",
             "code" => "unsupported_action"
           } = json_response(action_response, 404)
  end

  test "unauthenticated application-host requests use the browser gate", %{conn: conn} do
    response = post(conn, query_path("mission-missing"), %{})

    assert redirected_to(response) == "/console/sign-in"
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

    query_response =
      post_bridge(catalog, catalog_conn, mission.mission_id, %{"scope" => valid_scope})

    action_response =
      post_bridge(
        catalog,
        catalog_conn,
        mission.mission_id,
        %{"actionId" => "anything", "params" => %{}, "scope" => valid_scope},
        :actions
      )

    for response <- [query_response, action_response] do
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

    install_limits(scope, mission)
    {TestFixtures.member_conn(user), organization, mission, scope}
  end

  defp install_limits(scope, %Mission{} = mission),
    do: ApplicationInstallations.install(scope, HostContext.mission(mission.mission_id), "limits")

  defp host_path(mission_id),
    do: "/api/console/v1/missions/#{mission_id}/apps/limits/surfaces/manage/host"

  # The console's surface host mints the host session id, CSRF token and pinned scope.
  defp fetch_catalog(conn, %Mission{mission_id: mission_id}) do
    catalog_conn = get(conn, host_path(mission_id))
    {catalog_conn, json_response(catalog_conn, 200)["data"]["catalog"]}
  end

  defp query_path(mission_id), do: @bridge_suffix <> "/" <> mission_id <> "/query"

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
        :actions -> @bridge_suffix <> "/#{mission_id}/actions"
      end

    conn = bridge_conn(conn, catalog)

    conn =
      if endpoint == :actions,
        do: put_req_header(conn, "idempotency-key", "bridge-action-test"),
        else: conn

    post_json(conn, path, Map.merge(surface_request(endpoint), body))
  end

  defp surface_request(:query),
    do: %{
      "applicationKey" => "limits",
      "applicationVersion" => 1,
      "surfaceId" => "manage",
      "surfaceVersion" => 1,
      "queryId" => "cadence.limits.manage",
      "queryVersion" => 1
    }

  defp surface_request(:actions),
    do: %{
      "applicationKey" => "limits",
      "applicationVersion" => 1,
      "surfaceId" => "manage",
      "surfaceVersion" => 1
    }

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
