defmodule CadenceWeb.Console.MissionProvidersAPITest do
  @moduledoc "L12 mission providers: options, create, validate, sync, archive (setup.md §L12)."
  use CadenceWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Cadence.Auth.Scope
  alias Cadence.Control.Providers, as: ControlProviders
  alias Cadence.GroundNetworks.{ProviderAccountGrants, ProviderAccounts, ProviderCredentials}
  alias Cadence.GroundNetworks.ProviderError
  alias Cadence.TestSupport.FakeProviderClient
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!()
    member = TestFixtures.persist_user!()
    admin_membership = TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)
    mission = TestFixtures.persist_mission!(org)

    {:ok, _credential} =
      ProviderCredentials.create(
        org.organization_id,
        "pa-l12",
        %{
          provider_credential_ref: "provider-credential-l12",
          backend_type: :external,
          backend_key: "providers/l12"
        },
        manage_backend?: false
      )

    {:ok, _account, _version} =
      ProviderAccounts.create_for_system(
        org.organization_id,
        %{
          provider_account_id: "pa-l12",
          display_name: "Simulator Account",
          provider_type: :simulator,
          base_url: "http://simulator.test",
          environment_ref: "run-alpha",
          credential_ref: "provider-credential-l12",
          guardrails: %{"allowed_stations" => ["station-alpha", "station-beta"]}
        },
        %{"kind" => "system", "id" => "test"},
        validate_credential?: false
      )

    scope =
      Scope.new(%{
        user: admin,
        organization_id: org.organization_id,
        organization_membership: admin_membership
      })

    {:ok, grant} = ProviderAccountGrants.grant(scope, mission.mission_id, "pa-l12", %{})
    set_call_opts([])

    %{
      admin: admin,
      member: member,
      scope: scope,
      grant: grant,
      base: "/api/v1/missions/#{mission.mission_id}/providers"
    }
  end

  defp set_call_opts(extra) do
    original = Application.fetch_env(:cadence_web, :mission_provider_call_opts)

    Application.put_env(
      :cadence_web,
      :mission_provider_call_opts,
      [
        client: FakeProviderClient,
        credential_resolver: {FakeProviderClient, :resolve_credential}
      ] ++ extra
    )

    on_exit(fn ->
      case original do
        {:ok, opts} -> Application.put_env(:cadence_web, :mission_provider_call_opts, opts)
        :error -> Application.delete_env(:cadence_web, :mission_provider_call_opts)
      end
    end)
  end

  defp admin(c), do: TestFixtures.member_conn(c.admin)

  defp create!(c) do
    c
    |> admin()
    |> post(c.base, %{
      "grant_id" => c.grant.provider_account_grant_id,
      "display_name" => "Simulator",
      "policy_mode" => "approval_required",
      "permitted_resource_refs" => ["station-alpha"]
    })
    |> json_response(201)
    |> get_in(["data", "provider"])
  end

  test "options list the mission's grants; create binds one; the list has health and grant", c do
    assert %{"grants" => [option], "policy_modes" => [_, _], "deadline_behaviors" => [_, _]} =
             c |> admin() |> get(c.base <> "/options") |> json_response(200) |> Map.fetch!("data")

    assert %{"id" => _, "version" => 1, "account" => %{"id" => "pa-l12"}} = option

    provider = create!(c)

    assert %{
             "name" => "Simulator",
             "version" => 1,
             "policy_mode" => "approval_required",
             "grant" => %{"state" => "active", "version" => 1},
             "health" => %{"validate" => %{"status" => nil}, "sync" => %{"status" => nil}}
           } = provider

    assert %{"providers" => [%{"id" => id}], "permissions" => ["providers.manage"]} =
             c |> admin() |> get(c.base) |> json_response(200) |> Map.fetch!("data")

    assert id == provider["id"]

    assert %{"permissions" => []} =
             c.member
             |> TestFixtures.member_conn()
             |> get(c.base)
             |> json_response(200)
             |> Map.fetch!("data")

    assert c.member
           |> TestFixtures.member_conn()
           |> get(c.base <> "/options")
           |> json_response(403)
  end

  test "a policy without a mode lists as approval_required, never null", c do
    id = create!(c)["id"]

    Cadence.Repo.query!(
      "UPDATE mission_providers SET delivery_policy_document = delivery_policy_document #- '{value,mode}' WHERE provider_id = $1",
      [id]
    )

    assert %{rows: [[nil]]} =
             Cadence.Repo.query!(
               "SELECT delivery_policy_document #> '{value,mode}' FROM mission_providers WHERE provider_id = $1",
               [id]
             )

    assert %{"providers" => [%{"id" => ^id, "policy_mode" => "approval_required"}]} =
             c |> admin() |> get(c.base) |> json_response(200) |> Map.fetch!("data")
  end

  test "a direct binding (no account grant) lists account: null and grant: null", c do
    id = create!(c)["id"]

    Cadence.Repo.query!(
      "UPDATE mission_providers SET provider_account_id = NULL, provider_account_version = NULL, provider_account_grant_id = NULL, provider_account_grant_version = NULL WHERE provider_id = $1",
      [id]
    )

    assert %{"providers" => [%{"id" => ^id, "account" => nil, "grant" => nil}]} =
             c |> admin() |> get(c.base) |> json_response(200) |> Map.fetch!("data")
  end

  test "create refuses a stale or revoked grant and names bad fields", c do
    body = %{
      "grant_id" => c.grant.provider_account_grant_id,
      "display_name" => "Simulator",
      "policy_mode" => "approval_required"
    }

    assert %{"error" => %{"code" => "grant_changed", "details" => %{"version" => 1}}} =
             c
             |> admin()
             |> post(c.base, Map.put(body, "expected_grant_version", 4))
             |> json_response(409)

    for {field, value} <- [
          {"display_name", " "},
          {"policy_mode", "whenever"},
          {"permitted_resource_refs", ["station-gamma"]}
        ] do
      assert %{"error" => %{"details" => %{^field => _}}} =
               c |> admin() |> post(c.base, Map.put(body, field, value)) |> json_response(422)
    end

    {:ok, _revoked} =
      ControlProviders.revoke_account_grant(c.scope, c.grant.provider_account_grant_id, "Ended")

    assert %{"error" => %{"code" => "grant_revoked"}} =
             c |> admin() |> post(c.base, body) |> json_response(409)
  end

  test "validate and sync are results: ok, refused, and past the deadline", c do
    path = c.base <> "/" <> create!(c)["id"]

    assert %{"result" => %{"ok" => true, "message" => nil}, "provider" => %{"health" => health}} =
             c |> admin() |> post(path <> "/validate") |> json_response(200) |> Map.fetch!("data")

    assert health["validate"]["status"] == "healthy"

    assert %{"result" => %{"ok" => true, "stations" => 0}} =
             c |> admin() |> post(path <> "/sync") |> json_response(200) |> Map.fetch!("data")

    set_call_opts(validate_response: {:error, ProviderError.unavailable(:econnrefused)})

    assert %{
             "result" => %{"ok" => false, "message" => "The provider couldn't be reached."},
             "provider" => %{"health" => %{"validate" => %{"status" => "failed"}}}
           } =
             c |> admin() |> post(path <> "/validate") |> json_response(200) |> Map.fetch!("data")

    set_call_opts(
      deadline_ms: 50,
      validate_response: fn ->
        Process.sleep(1_000)
        {:ok, %{}}
      end
    )

    assert %{
             "result" => %{"ok" => false, "message" => "The provider didn't answer in time."},
             "provider" => %{"health" => %{"validate" => %{"status" => "failed"}}}
           } =
             c |> admin() |> post(path <> "/validate") |> json_response(200) |> Map.fetch!("data")

    assert c.member |> TestFixtures.member_conn() |> post(path <> "/sync") |> json_response(403)
  end

  test "archive needs a reason, works after the grant is revoked, then the provider is gone", c do
    path = c.base <> "/" <> create!(c)["id"]

    assert %{"error" => %{"details" => %{"reason" => "Say why."}}} =
             c |> admin() |> post(path <> "/archive", %{}) |> json_response(422)

    {:ok, _revoked} =
      ControlProviders.revoke_account_grant(c.scope, c.grant.provider_account_grant_id, "Ended")

    assert %{"provider" => %{"status" => %{"lifecycle_state" => "archived"}}} =
             c
             |> admin()
             |> post(path <> "/archive", %{"reason" => "Contract ended"})
             |> json_response(200)
             |> Map.fetch!("data")

    assert %{"error" => %{"code" => "provider_not_found"}} =
             c |> admin() |> post(path <> "/validate") |> json_response(404)

    assert %{"providers" => []} =
             c |> admin() |> get(c.base) |> json_response(200) |> Map.fetch!("data")
  end
end
