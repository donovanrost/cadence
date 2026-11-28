defmodule CadenceWeb.Console.MissionProvidersAPITest do
  @moduledoc "L12 mission providers: options, create, validate, sync, archive (setup.md §L12)."
  use CadenceWeb.ConnCase, async: false

  @moduletag :capture_log

  alias Cadence.Auth.{Scope, ServiceIdentity}
  alias Cadence.Control.Providers, as: ControlProviders
  alias Cadence.DeliveryCredentialFixtures
  alias Cadence.GroundNetworks.{ProviderAccountGrants, ProviderAccounts, ProviderCredentials}
  alias Cadence.GroundNetworks.{ProviderAudit, ProviderError}
  alias Cadence.Platform.ScopedReadUpdates
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
      mission_id: mission.mission_id,
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

  test "issues, rotates and terminally revokes a fingerprint under the same binding reference",
       c do
    provider = create!(c)["id"]
    delivery_issuer!()
    path = c.base <> "/#{provider}/delivery-credentials/downlink"
    issue = %{"reason" => "initial_enrollment", "csr_pem" => DeliveryCredentialFixtures.csr()}

    assert %{
             "data" => %{
               "certificate_pem" => "-----BEGIN CERTIFICATE-----" <> _,
               "credential" => credential
             }
           } =
             c |> admin() |> post(path <> "/issue", issue) |> json_response(201)

    ref = credential["credential_ref"]

    assert [%{"state" => "current", "generation" => 1, "fingerprint" => first}] =
             credential["generations"]

    rotate = %{
      "reason" => "scheduled_rotation",
      "csr_pem" => DeliveryCredentialFixtures.csr(),
      "expected_generation" => 1
    }

    assert %{
             "data" => %{
               "credential" => %{"credential_ref" => ^ref, "generations" => generations}
             }
           } =
             c |> admin() |> post(path <> "/rotate", rotate) |> json_response(200)

    assert [
             %{"state" => "current", "generation" => 2, "fingerprint" => current},
             %{
               "state" => "previous",
               "generation" => 1,
               "fingerprint" => ^first,
               "overlap_ends_at" => overlap
             }
           ] = generations

    assert is_binary(overlap)
    assert c |> admin() |> post(path <> "/rotate", rotate) |> json_response(409)

    revoke = %{"reason" => "suspected_compromise", "fingerprint" => current}

    assert %{"data" => %{"generations" => revoked}} =
             c |> admin() |> post(path <> "/revoke", revoke) |> json_response(200)

    assert Enum.all?(revoked, &(&1["state"] == "revoked"))
    assert List.first(revoked)["fingerprint"] == current

    assert c |> admin() |> post(path <> "/issue", issue) |> json_response(422)

    assert %{
             "data" => %{
               "credential" => %{
                 "credential_ref" => ^ref,
                 "generations" => [%{"state" => "current", "generation" => 3} | _]
               }
             }
           } =
             c
             |> admin()
             |> post(
               path <> "/issue",
               Map.put(issue, "csr_pem", DeliveryCredentialFixtures.csr())
             )
             |> json_response(201)

    assert %{"data" => %{"retired_at" => retired}} =
             c
             |> admin()
             |> post(path <> "/revoke", %{
               "reason" => "retired_binding",
               "target" => "binding"
             })
             |> json_response(200)

    assert is_binary(retired)
    assert c |> admin() |> post(path <> "/issue", issue) |> json_response(409)

    entries =
      ProviderAudit.list_entries(c.scope.organization_id,
        mission_id: c.mission_id,
        actions: [
          "provider_delivery_credential.issue",
          "provider_delivery_credential.rotate",
          "provider_delivery_credential.revoke"
        ]
      )

    assert length(entries) == 5

    assert Enum.all?(
             entries,
             &(&1.actor_document["id"] == c.admin.user_id and &1.credential_ref == ref)
           )

    refute inspect(entries) =~ "BEGIN CERTIFICATE"
  end

  test "delivery credential actions are scoped and person-session only", c do
    provider = create!(c)["id"]
    delivery_issuer!()
    path = c.base <> "/#{provider}/delivery-credentials/downlink/issue"
    params = %{"reason" => "initial_enrollment", "csr_pem" => DeliveryCredentialFixtures.csr()}

    assert %{"error" => %{"code" => "invalid_csrf"}} =
             c
             |> admin()
             |> put_private(:plug_skip_csrf_protection, false)
             |> post(path, params)
             |> json_response(403)

    assert c.member |> TestFixtures.member_conn() |> post(path, params) |> json_response(403)

    assert {:ok, %{api_token: token}} =
             Cadence.Auth.issue_service_identity(
               ServiceIdentity.new(%{
                 organization_id: c.scope.organization_id,
                 mission_id: c.mission_id,
                 display_name: "Provider automation",
                 capabilities: [:mission_admin]
               }),
               c.scope
             )

    assert %{"error" => %{"code" => "service_not_allowed"}} =
             build_conn()
             |> put_req_header("authorization", "Bearer " <> token)
             |> post(path, params)
             |> json_response(403)

    other = TestFixtures.persist_org!()
    outsider = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(outsider, other, role: :organization_admin)

    assert outsider |> TestFixtures.member_conn() |> post(path, params) |> json_response(404)
  end

  defp delivery_issuer! do
    previous = Application.get_env(:cadence, :provider_delivery_issuer)

    Application.put_env(
      :cadence,
      :provider_delivery_issuer,
      DeliveryCredentialFixtures.issuer_options()
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:cadence, :provider_delivery_issuer, previous)
      else
        Application.delete_env(:cadence, :provider_delivery_issuer)
      end
    end)
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
             "health" => %{"validate" => %{"status" => nil}, "sync" => %{"status" => nil}},
             # #968: no sync yet, so no declared orbit source, and nothing uploaded.
             "ephemeris" => %{
               "orbit_source" => nil,
               "uploaded" => 0,
               "failed" => 0,
               "pending" => 0,
               "not_ready" => 0,
               "lookup" => 0,
               "norad_id_missing" => 0
             }
           } = provider

    # The read sends exactly the documented ephemeris keys (setup.md), not_ready included.
    assert provider["ephemeris"] |> Map.keys() |> Enum.sort() ==
             ~w(failed lookup norad_id_missing not_ready orbit_source pending uploaded)

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

  test "create, validate, sync and archive publish providers; archive publishes attention", c do
    ScopedReadUpdates.subscribe(:providers_changed, c.scope.organization_id, c.mission_id)
    path = c.base <> "/" <> create!(c)["id"]
    assert_receive {:providers_changed, _org, _mission}

    for action <- ["/validate", "/sync"] do
      c |> admin() |> post(path <> action) |> json_response(200)
      assert_receive {:providers_changed, _org, _mission}
    end

    set_call_opts(validate_response: {:error, ProviderError.unavailable(:econnrefused)})
    c |> admin() |> post(path <> "/validate") |> json_response(200)
    assert_receive {:providers_changed, _org, _mission}

    ScopedReadUpdates.subscribe(:attention_changed, c.scope.organization_id, c.mission_id)
    c |> admin() |> post(path <> "/archive", %{"reason" => "Done"}) |> json_response(200)
    assert_receive {:providers_changed, _org, _mission}
    # The archived provider leaves the provider_ephemeris findings too.
    assert_receive {:attention_changed, _org, _mission}

    c |> admin() |> post(path <> "/archive", %{}) |> json_response(422)
    refute_receive {:providers_changed, _org, _mission}, 50
  end
end
