defmodule CadenceWeb.Console.ProviderAccountAPITest do
  @moduledoc "PA1 provider accounts (read and test)."
  use CadenceWeb.ConnCase, async: false

  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}
  alias Cadence.Secrets.{EnvBackend, ResolverConfiguration}
  alias CadenceWeb.TestFixtures

  test "lists accounts with status and permissions; members can't read" do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!()
    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    TestFixtures.grant_membership!(member, org, role: :member)

    {:ok, _credential} =
      ProviderCredentials.create(
        org.organization_id,
        "pa-sim",
        %{
          provider_credential_ref: "cred-sim",
          backend_type: :external,
          backend_key: "providers/sim"
        },
        manage_backend?: false
      )

    {:ok, _account, _version} =
      ProviderAccounts.create_for_system(
        org.organization_id,
        %{
          provider_account_id: "pa-sim",
          display_name: "Simulator Account",
          provider_type: :simulator,
          base_url: "http://simulator.test",
          environment_ref: "run-alpha",
          credential_ref: "cred-sim"
        },
        %{"kind" => "system", "id" => "test"},
        validate_credential?: false
      )

    base = "/api/console/v1/organizations/#{org.organization_id}/provider-accounts"

    data =
      admin |> TestFixtures.member_conn() |> get(base) |> json_response(200) |> Map.fetch!("data")

    assert [
             %{
               "id" => "pa-sim",
               "name" => "Simulator Account",
               "provider" => %{"key" => "simulator"},
               "status" => "not_checked",
               "missions" => [],
               "expires_at" => nil
             }
           ] = data["accounts"]

    assert data["permissions"] == ["provider_accounts.manage"]
    assert Enum.any?(data["adapters"], &(&1["key"] == "simulator"))

    assert member |> TestFixtures.member_conn() |> get(base) |> json_response(403)

    missing = admin |> TestFixtures.member_conn() |> post(base <> "/nope/test", %{})
    assert json_response(missing, 404)["error"]["code"] == "provider_account_not_found"
  end

  test "adds and edits an account by secret reference; Test says which part failed" do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    base = "/api/console/v1/organizations/#{org.organization_id}"
    conn = fn -> TestFixtures.member_conn(admin) end

    schema = conn.() |> get(base <> "/provider-adapters/simulator/schema") |> json_response(200)
    paths = Enum.map(schema["data"]["fields"], & &1["path"])
    assert "credential.key" in paths and "base_url" in paths

    # The console offers polling or off (ingestion), polling by default.
    assert %{"type" => "enum", "default" => "polling", "enum" => choices} =
             Enum.find(schema["data"]["fields"], &(&1["path"] == "event_ingestion_mode"))

    assert Enum.map(choices, & &1["value"]) == ["polling", "disabled"]
    refute Enum.any?(schema["data"]["fields"], &(&1["type"] == "password"))

    body = %{
      "provider_key" => "simulator",
      "name" => "Sim",
      "settings" => %{"base_url" => "http://sim.test", "environment_ref" => "run-a"},
      "credential" => %{"backend" => "external", "key" => "providers/sim/control-plane"}
    }

    # Drift sweep: a refused create names the field, before anything is registered.
    bad_url = put_in(body, ["settings", "base_url"], "sim.test")

    assert %{"code" => "invalid_params", "details" => %{"settings.base_url" => _}} =
             conn.()
             |> post(base <> "/provider-accounts", bad_url)
             |> json_response(422)
             |> Map.fetch!("error")

    assert %{"name" => _} =
             conn.()
             |> post(base <> "/provider-accounts", %{body | "name" => "  "})
             |> json_response(422)
             |> get_in(["error", "details"])

    created =
      conn.()
      |> post(base <> "/provider-accounts", %{body | "name" => "  Sim "})
      |> json_response(201)
      |> Map.fetch!("data")

    assert %{"id" => id, "version" => 1} = created
    assert Map.keys(created) |> Enum.sort() == ["id", "version"]

    assert [%{"name" => "Sim"}] =
             conn.()
             |> get(base <> "/provider-accounts")
             |> json_response(200)
             |> get_in(["data", "accounts"])

    assert %{"version" => 2} =
             conn.()
             |> put(base <> "/provider-accounts/" <> id, %{
               "settings" => %{"base_url" => "http://sim2.test"}
             })
             |> json_response(201)
             |> Map.fetch!("data")

    rename = conn.() |> put(base <> "/provider-accounts/" <> id, %{"name" => "Sim (renamed)"})
    assert %{"version" => nil} = json_response(rename, 201)["data"]

    [renamed] =
      conn.()
      |> get(base <> "/provider-accounts")
      |> json_response(200)
      |> get_in(["data", "accounts"])

    assert renamed["name"] == "Sim (renamed)"

    # PA1 history: newest first, with what each version changed.
    history =
      conn.()
      |> get(base <> "/provider-accounts/#{id}/versions")
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"current_version" => 2, "name" => "Sim (renamed)"} = history

    assert [%{"version" => 2, "changes" => changes}, %{"version" => 1, "changes" => []}] =
             history["versions"]

    assert %{"label" => "Endpoint", "before" => "http://sim.test", "after" => "http://sim2.test"} =
             Enum.find(changes, &(&1["field"] == "base_url"))

    admin_id = admin.user_id
    assert %{"actor" => %{"kind" => "user", "id" => ^admin_id}} = hd(history["versions"])

    assert conn.() |> get(base <> "/provider-accounts/nope/versions") |> json_response(404)

    blank = conn.() |> put(base <> "/provider-accounts/" <> id, %{"name" => " "})
    assert json_response(blank, 422)["error"]["details"]["name"]

    # No secret manager in tests: the reference can't resolve, and Test says so.
    test = conn.() |> post(base <> "/provider-accounts/#{id}/test", %{}) |> json_response(200)
    assert %{"ok" => false, "checked" => ["reference"], "failed" => "reference"} = test["data"]

    retired =
      conn.()
      |> delete(base <> "/provider-accounts/" <> id, %{"reason" => "No longer used"})
      |> json_response(200)

    assert %{"id" => ^id, "state" => "archived"} = retired["data"]

    # AU1: the account's changes are in the organization audit, by who made them.
    audit =
      conn.()
      |> get(base <> "/audit?kinds=provider_accounts")
      |> json_response(200)
      |> get_in(["data", "events"])

    actions = Enum.map(audit, & &1["action"])
    # Events name the account by its current name; the rename says both.
    assert "Added provider account Sim (renamed)" in actions
    assert "Changed Sim (renamed)'s settings (version 2)" in actions
    assert "Renamed provider account Sim to Sim (renamed)" in actions
    assert "Retired provider account Sim (renamed)" in actions
    assert Enum.all?(audit, &(&1["actor"]["kind"] == "user"))

    assert conn.()
           |> get(base <> "/provider-accounts")
           |> json_response(200)
           |> get_in(["data", "accounts"]) == []

    # An env credential may only name a variable this environment allows (api-ops 11-15).
    denied = put_in(body, ["credential", "backend"], "env")

    assert json_response(conn.() |> post(base <> "/provider-accounts", denied), 422)["error"][
             "details"
           ]
           |> Map.take(["credential.key", "credential.backend"])
           |> map_size() == 1

    # ...another organization's prefix is refused too; its own prefix works.
    other = put_in(denied, ["credential", "key"], "CADENCE_TENANT_SOMEONE_ELSE_TOKEN")

    assert json_response(conn.() |> post(base <> "/provider-accounts", other), 422)["error"][
             "details"
           ]
           |> Map.take(["credential.key", "credential.backend"])
           |> map_size() == 1

    own_key = EnvBackend.tenant_prefix(org.organization_id) <> "SIM_TOKEN"
    env = put_in(denied, ["credential", "key"], own_key)
    env_conn = conn.() |> post(base <> "/provider-accounts", env)

    if ResolverConfiguration.provider_options()[
         :allow_local_provider_credentials?
       ],
       do: assert(json_response(env_conn, 201)),
       else: assert(json_response(env_conn, 422)["error"]["details"]["credential.backend"])

    bad = conn.() |> post(base <> "/provider-accounts", Map.delete(body, "credential"))
    assert json_response(bad, 422)["error"]["details"]["credential"]
  end

  test "event ingestion: set on create, kept by other edits, changed by its own; never polled when disabled" do
    org = TestFixtures.persist_org!()
    admin = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    base = "/api/console/v1/organizations/#{org.organization_id}"
    conn = fn -> TestFixtures.member_conn(admin) end

    body = %{
      "provider_key" => "simulator",
      "name" => "Quiet sim",
      "settings" => %{
        "base_url" => "http://sim.test",
        "environment_ref" => "run-a",
        "event_ingestion_mode" => "disabled"
      },
      "credential" => %{"backend" => "external", "key" => "providers/sim/quiet"}
    }

    # An unknown mode is refused on the field, before anything is registered.
    refused = put_in(body, ["settings", "event_ingestion_mode"], "sometimes")

    assert %{"settings.event_ingestion_mode" => _} =
             conn.()
             |> post(base <> "/provider-accounts", refused)
             |> json_response(422)
             |> get_in(["error", "details"])

    mode = fn id ->
      conn.()
      |> get(base <> "/provider-accounts")
      |> json_response(200)
      |> get_in(["data", "accounts"])
      |> Enum.find(&(&1["id"] == id))
      |> Map.fetch!("event_ingestion_mode")
    end

    polled? = fn id ->
      Enum.any?(
        ProviderAccounts.list_polling_accounts(),
        fn {account, _version} -> account.provider_account_id == id end
      )
    end

    assert %{"id" => id} =
             conn.()
             |> post(base <> "/provider-accounts", body)
             |> json_response(201)
             |> Map.fetch!("data")

    assert mode.(id) == "disabled"
    refute polled?.(id)

    # Another setting's edit keeps the mode (a new version merges onto the current one).
    conn.()
    |> put(base <> "/provider-accounts/" <> id, %{"settings" => %{"region_ref" => "eu"}})
    |> json_response(201)

    assert mode.(id) == "disabled"

    assert %{"version" => 3} =
             conn.()
             |> put(base <> "/provider-accounts/" <> id, %{
               "settings" => %{"event_ingestion_mode" => "polling"}
             })
             |> json_response(201)
             |> Map.fetch!("data")

    assert mode.(id) == "polling"
    assert polled?.(id)

    assert %{"settings.event_ingestion_mode" => _} =
             conn.()
             |> put(base <> "/provider-accounts/" <> id, %{
               "settings" => %{"event_ingestion_mode" => 1}
             })
             |> json_response(422)
             |> get_in(["error", "details"])

    # Without the setting, a create polls, as before.
    {_, plain} = pop_in(body, ["settings", "event_ingestion_mode"])
    plain = put_in(plain, ["credential", "key"], "providers/sim/plain")

    assert %{"id" => plain_id} =
             conn.()
             |> post(base <> "/provider-accounts", plain)
             |> json_response(201)
             |> Map.fetch!("data")

    assert mode.(plain_id) == "polling"
  end
end
