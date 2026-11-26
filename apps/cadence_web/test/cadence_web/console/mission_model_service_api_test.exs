defmodule CadenceWeb.Console.MissionModelServiceAPITest do
  @moduledoc """
  #748 (#747, one public API): Mission Model & Spacecraft's old bearer `/api` endpoints are gone,
  and their `/api/v1` equivalents take a service identity's bearer only where the action opts in
  (`CadenceWeb.Console.ServiceAccess`). Each ported action is reached by a person's session and an
  opted-in service; a service is refused what stays a person's (reimport, rollout, activation
  decisions).
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.ServiceIdentity
  alias CadenceWeb.TestFixtures

  @yaml """
  packets:
    - name: HEALTH
      apid: 42
      items:
        - name: mode
          data_type: uint
          bit_offset: 0
          bit_size: 8
  commands: []
  """

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-001")

    {:ok, %{api_token: token}} =
      Cadence.Auth.issue_service_identity(
        ServiceIdentity.new(%{
          service_identity_id: "svc-catalog-#{System.unique_integer([:positive])}",
          organization_id: org.organization_id,
          mission_id: mission.mission_id,
          display_name: "Catalog pipeline",
          capabilities: [:mission_admin]
        }),
        %Cadence.Auth.Scope{
          actor_kind: :user,
          organization_id: org.organization_id,
          user: %Cadence.Accounts.User{user_id: user.user_id}
        }
      )

    %{
      user: user,
      mission: mission,
      craft: craft,
      token: token,
      base: "/api/v1/missions/#{mission.mission_id}"
    }
  end

  # Phoenix.ConnTest skips CSRF by default; a bearer request must not need it, so check it.
  defp service(c),
    do:
      build_conn()
      |> put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("authorization", "Bearer " <> c.token)

  defp person(c), do: TestFixtures.member_conn(c.user)

  defp upload(conn, c) do
    path = Path.join(System.tmp_dir!(), "catalog-748-#{System.unique_integer([:positive])}.yaml")
    File.write!(path, @yaml)
    on_exit(fn -> File.rm(path) end)

    post(conn, "#{c.base}/catalog/imports", %{
      "name" => "Pipeline catalog",
      "revision_label" => "R1",
      "file" => %Plug.Upload{
        path: path,
        filename: "mission.yaml",
        content_type: "application/yaml"
      }
    })
  end

  defp imported!(c) do
    assert %{"import_run_id" => run_id} =
             c |> service() |> upload(c) |> json_response(202) |> Map.fetch!("data")

    {:ok, run} =
      Cadence.Catalog.fetch_import_run(c.mission.organization_id, c.mission.mission_id, run_id)

    TestFixtures.complete_catalog_import_run!(run)
  end

  test "the old bearer endpoints are gone, with no alias", c do
    old = "/api/organizations/#{c.mission.organization_id}/missions/#{c.mission.mission_id}"

    for path <-
          ~w(/catalog/importers /catalog_artifacts /catalog_import_runs /spacecraft
             /packet_definitions /activations/active /activation_requests) do
      conn = c |> service() |> get(old <> path)
      assert conn.status == 404, "#{path} answered #{conn.status}"
    end
  end

  test "a service imports a catalog as itself and reads the run, the artifact and its APIDs", c do
    run = imported!(c)
    assert %{"actor_kind" => "service"} = run.requested_by

    detail =
      c
      |> service()
      |> get("#{c.base}/catalog/imports/#{run.import_run_id}")
      |> json_response(200)

    assert detail["data"]["status"] == "succeeded"
    revision_id = detail["data"]["revision"]["id"]

    # #752: the current revision names the composition a profile pins (D3).
    assert %{"data" => %{"databases" => [_], "database" => %{"current_revision" => current}}} =
             c |> service() |> get("#{c.base}/catalog") |> json_response(200)

    assert current["id"] == revision_id
    assert is_binary(current["composition_id"])
    assert current["composition_id"] == detail["data"]["revision"]["composition_id"]

    assert %{"data" => %{"importers" => [_ | _]}} =
             c |> service() |> get("#{c.base}/catalog/importers") |> json_response(200)

    assert c
           |> service()
           |> get("#{c.base}/catalog/artifacts/#{run.artifact_id}")
           |> json_response(200)

    assert %{status: 200} =
             c |> service() |> get("#{c.base}/catalog/artifacts/#{run.artifact_id}/download")

    assert %{"data" => %{"apids" => [%{"apid" => 42, "packets" => ["HEALTH"]}]}} =
             c
             |> service()
             |> get("#{c.base}/catalog/revisions/#{revision_id}/apids")
             |> json_response(200)
  end

  test "a service reads spacecraft: the directory, names and one craft", c do
    assert c |> service() |> get("#{c.base}/spacecraft") |> json_response(200)

    assert %{"data" => %{"names" => [%{"name" => "EARENDIL-001"}]}} =
             c |> service() |> get("#{c.base}/spacecraft/names") |> json_response(200)

    assert c
           |> service()
           |> get("#{c.base}/spacecraft/#{c.craft.spacecraft_id}")
           |> json_response(200)
  end

  test "a person's session reaches the same actions", c do
    assert %{"import_run_id" => _run_id} =
             c |> person() |> upload(c) |> json_response(202) |> Map.fetch!("data")

    for path <- ~w(/catalog /catalog/importers /spacecraft /spacecraft/names) do
      assert %{status: 200} = c |> person() |> get(c.base <> path)
    end

    assert %{status: 200} = c |> person() |> get("#{c.base}/spacecraft/#{c.craft.spacecraft_id}")
  end

  test "a service is refused what stays a person's", c do
    run = imported!(c)
    revision = TestFixtures.fetch_catalog_revision_for_run!(run)

    refused = [
      {:post, "#{c.base}/catalog/artifacts/#{run.artifact_id}/reimport"},
      {:get, "#{c.base}/catalog/revisions/#{revision.catalog_revision_id}/rollout"},
      {:get, "#{c.base}/activations"}
    ]

    for {method, path} <- refused do
      conn = c |> service() |> dispatch(@endpoint, method, path, %{})

      assert %{"error" => %{"code" => "service_not_allowed"}} = json_response(conn, 403),
             "#{method} #{path}"
    end
  end

  # commanding's review of #748: a service import keeps four-eyes. The person who issued the
  # service identity counts as the importer, so they can't approve its revision; another admin can.
  test "the service's issuer can't approve the revision it imported; another admin can", c do
    org = %Cadence.Organizations.Organization{organization_id: c.mission.organization_id}
    issuer = TestFixtures.persist_user!(display_name: "Ivo P.")
    other = TestFixtures.persist_user!(display_name: "Ana R.")

    for user <- [issuer, other],
        do: TestFixtures.grant_membership!(user, org, role: :organization_admin)

    {:ok, %{api_token: token}} =
      Cadence.Auth.issue_service_identity(
        ServiceIdentity.new(%{
          service_identity_id: "svc-issued-#{System.unique_integer([:positive])}",
          organization_id: c.mission.organization_id,
          mission_id: c.mission.mission_id,
          display_name: "Issued pipeline",
          capabilities: [:mission_admin]
        }),
        %Cadence.Auth.Scope{
          actor_kind: :user,
          organization_id: c.mission.organization_id,
          user: %Cadence.Accounts.User{user_id: issuer.user_id}
        }
      )

    run = imported!(%{c | token: token})
    model = TestFixtures.fetch_catalog_revision_for_run!(run).mission_model_revision_id
    path = "#{c.base}/mission-model-revisions/#{model}"

    decide = fn user ->
      report =
        user
        |> TestFixtures.member_conn()
        |> post(path <> "/comparison", %{})
        |> json_response(201)
        |> get_in(["data", "report_id"])

      user
      |> TestFixtures.member_conn()
      |> post(path <> "/approve", %{"comparison_report_id" => report})
    end

    assert json_response(decide.(issuer), 403)["error"]["code"] ==
             "mission_model_self_approval_forbidden"

    assert %{"data" => %{"status" => "approved"}} = json_response(decide.(other), 200)
  end
end
