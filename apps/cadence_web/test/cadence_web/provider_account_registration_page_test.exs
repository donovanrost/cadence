defmodule CadenceWeb.ProviderAccountRegistrationPageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Cadence.Auth.Scope
  alias Cadence.GroundNetworks.{ProviderAccounts, ProviderCredentials}
  alias CadenceWeb.TestFixtures

  setup do
    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization_membership: membership
      })

    previous = Application.fetch_env(:cadence_web, :provider_account_live_opts)

    Application.put_env(:cadence_web, :provider_account_live_opts,
      manage_backend?: false,
      validate_credential?: false
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:cadence_web, :provider_account_live_opts, value)
        :error -> Application.delete_env(:cadence_web, :provider_account_live_opts)
      end
    end)

    %{conn: TestFixtures.member_conn(user), scope: scope}
  end

  test "refresh and validation preserve page identity; sandbox save consumes the instance",
       context do
    {:ok, view, _} = live(context.conn, "/provider-accounts/new")
    page = page(view)
    assert page["id"] == "comms.provider-account-registration"
    assert page["status"] == "ready"
    assert_producer(page)
    refresh(view, "/provider-accounts/new")
    assert page(view) == page
    input = input(page)
    validation = action(view, page, "validate", input)
    assert validation["ok"]
    assert validation["snapshot"]["status"] == "ok"

    assert validation["snapshot"]["data"]["result"]["patch"]["form"]["fields"][
             "provider_account_id"
           ]["value"] == input["provider_account"]["provider_account_id"]

    assert page(view)["token"] == page["token"]
    saved = action(view, page, "save", input)
    assert saved["snapshot"]["status"] == "ok"
    id = input["provider_account"]["provider_account_id"]
    assert saved["snapshot"]["data"]["result"]["navigate"] == "/provider-accounts/" <> id
    assert {:ok, account, _} = ProviderAccounts.fetch(context.scope, id)
    assert account.display_name == "Host registration"
    refute action(view, page, "save", input)["ok"]
    refresh(view, "/provider-accounts/new")
    assert page(view)["status"] == "unavailable"
    refute action(view, page, "save", input)["ok"]
  end

  test "tampered references, malformed inputs and stale path or tokens do not execute", context do
    {:ok, view, _} = live(context.conn, "/provider-accounts/new")
    original = page(view)
    values = input(original)["provider_account"]

    for key <- ["provider_account_id", "credential_ref"] do
      reply =
        action(view, original, "save", %{"provider_account" => Map.put(values, key, "foreign")})

      assert reply["snapshot"]["status"] == "rejected"
    end

    for invalid <- [
          nil,
          [],
          %{"provider_account" => []},
          %{"provider_account" => Map.put(values, "display_name", %{})}
        ] do
      assert action(view, original, "save", invalid)["snapshot"]["status"] == "rejected"
    end

    refute action(view, Map.put(original, "token", Ecto.UUID.generate()), "save", input(original))[
             "ok"
           ]

    refresh(view, "/missions")
    refute action(view, original, "save", input(original))["ok"]
    refresh(view, "/provider-accounts/new")
    refute page(view)["token"] == original["token"]

    refute page(view)["data"]["form"]["fields"]["provider_account_id"] ==
             original["data"]["form"]["fields"]["provider_account_id"]

    refute action(view, original, "save", input(original))["ok"]
    assert {:ok, []} = ProviderAccounts.list(context.scope)
  end

  test "uncertain failure is sanitized and consumed; refresh cannot retry partial effects",
       context do
    {:ok, view, _} = live(context.conn, "/provider-accounts/new")
    page = page(view)
    # The account rejects an invalid event mode after credential registration.
    input = put_in(input(page), ["provider_account", "event_ingestion_mode"], "invalid-mode")
    assert action(view, page, "save", input)["snapshot"] == %{"status" => "unknown"}
    refute action(view, page, "save", input)["ok"]
    assert {:ok, []} = ProviderAccounts.list(context.scope)
    credential_ref = input["provider_account"]["credential_ref"]

    assert {:ok, _} =
             ProviderCredentials.fetch(
               context.scope.organization_id,
               input["provider_account"]["provider_account_id"],
               credential_ref
             )

    refresh(view, "/provider-accounts/new")
    assert page(view)["status"] == "unavailable"
  end

  test "revoked session and member cannot use the registration action", context do
    {:ok, view, _} = live(context.conn, "/provider-accounts/new")
    page = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(context.conn, :user_session_token))
    render_hook(view, "host:organization-page", request(page, "save", input(page)))
    assert_redirect(view, "/sign-in")
    assert {:ok, []} = ProviderAccounts.list(context.scope)
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), "/provider-accounts/new")
    member = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(member, org, role: :member)

    assert {:error, {:redirect, %{to: "/"}}} =
             live(TestFixtures.member_conn(member), "/provider-accounts/new")
  end

  defp page(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"][
        "organization_module_page"
      ]

  defp request(page, event, input),
    do: %{
      "id" => page["id"],
      "token" => page["token"],
      "path" => "/provider-accounts/new",
      "event" => event,
      "input" => input
    }

  defp action(view, page, event, input) do
    render_hook(view, "host:organization-page", request(page, event, input))
    assert_reply(view, reply)
    Jason.decode!(Jason.encode!(reply))
  end

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp input(page) do
    form = page["data"]["form"]

    fields =
      Map.values(form["fields"]) ++
        Enum.flat_map(form["connector"]["configuration"]["sections"], & &1["fields"])

    values =
      Map.new(fields, &{&1["key"], &1["value"]})
      |> Map.merge(%{
        "display_name" => "Host registration",
        "base_url" => "https://provider.example.test",
        "environment_ref" => "test",
        "backend_key" => "fixture/registration",
        "max_quota" => "0"
      })

    %{"provider_account" => values}
  end

  defp assert_producer(page) do
    checker =
      Path.expand(
        "../../../../frontend/modules/communications/src/features/provider-accounts/producer-render-check.mjs",
        __DIR__
      )

    samples = [
      %{
        component: "ProviderAccountNew",
        props: page["data"],
        ids: ["provider-account-new-page", "provider-account-form"]
      }
    ]

    {output, status} =
      System.cmd(System.find_executable("node"), [checker, Jason.encode!(samples)],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
